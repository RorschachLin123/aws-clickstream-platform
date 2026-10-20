# v0.1: reproducible Kinesis → Flink → Iceberg → Athena demo

Implementation is under verification. Compilation, mocks and a generated manifest are not evidence of cloud delivery. Record live results in `docs/v01-acceptance.md` after the demonstration.

## Build and prepare

Requires Python 3.11+, Java 11, Maven and the Terraform version pinned in CI. The Flink job uses the supported Flink 1.20 runtime and Kinesis connector 5.0.0-1.20. AWS SDK clients are aligned to 2.33.0 rather than packaging two incompatible SDK versions. Existing `clickstream` profile assumes the bounded project operator through short-lived credentials.

```bash
python3 -m venv .venv
.venv/bin/pip install -e .
PYTHONPATH=src .venv/bin/python -m unittest discover -s tests -v
mvn -B -f flink/pom.xml verify
.venv/bin/clickstream generate --out demo-output/run1 --run-id v01-seed42 --seed 42 --journeys 500
```

The fixed fixture contains 1,030 records: 500 impressions, 280 clicks, 127 installs, 103 activations and 20 payments. Its NDJSON SHA-256 is `3b8c43992a0985426ca6ccf86eb56d19a38a7c06851657078ddfddd47c635cbe`. No wall clock or external data affects generation. Every event has event_id, run_id, impression_id, user_id, app_id, campaign_id, event_type, UTC event_time and integer amount_cents.

## Deploy and run

Before enabling the pipeline, an account administrator must review the additional deployment/runtime permissions and extend the fixed boundary for the named Flink role/application and Athena workgroup. The operator must not gain permission to change its own boundary. Existing skeleton grants do not cover this phase. The concrete plan and bounded runtime/cost scope must be authorized before apply.

Set `enable_stream=true` and `enable_pipeline=true` in ignored local variables. The default remains false. Set `flink_jar_path` if building outside `flink/target`. Initialize the existing backend per the skeleton runbook. Do not create a second backend or mix state files.

```bash
AWS_PROFILE=clickstream terraform -chdir=infra plan -out=deployment.tfplan
# Review exact resources, permissions and expected cost before apply.
AWS_PROFILE=clickstream terraform -chdir=infra apply deployment.tfplan
.venv/bin/clickstream --profile clickstream start
.venv/bin/python tools/record_demo.py --profile clickstream --dataset demo-output/run1 --out demo-output/run1/evidence
```

The recorder invokes publication and reconciliation once, saves the acknowledgement receipt and Athena verification, and attempts a graceful stop in its finally block. It writes demo.cast plus a standalone demo.html player with actual elapsed timestamps. Do not run a second publication for the same run. Starting or stopping the application may take several minutes. Enforce an external teardown deadline for the live session; do not wait for the monthly budget notification. Defaults: parallelism 1, autoscaling off, one KPU for processing plus service overhead, 30-second checkpoints, three-day logs, Athena engine 3 with an enforced 10 MiB scan cap per query. Reconciliation retries a bounded number of times for checkpoint visibility and records each query ID/scanned bytes; it fails on missing, extra, duplicate or altered rows.

The producer's role is write-only. Publication automatically assumes the named project producer role for 900 seconds using credentials held only in memory; the operator handles start/reconcile/cleanup. A local receipt is created before the first send. An interrupted or ambiguous request leaves IN_PROGRESS; investigate with Athena instead of deleting the receipt and replaying. Only explicitly rejected records are retried. Acknowledgement is not proof of table delivery. This baseline append-only sink does not deduplicate a deliberate producer rerun. A fresh run_id is required for a new ingestion into an existing table.

Iceberg v2 tables are created by the Flink job through GlueCatalog and S3FileIO. Iceberg files live under `iceberg/`, outside S3 expiration rules. Checkpoint completion commits snapshots. No claim is made that billing thresholds or crash recovery have been tested by this baseline demo.

## Three-minute presentation script

1. Show the data path and seed/manifest hash. State that all events are synthetic and reproducible.
2. Show the live Flink RUNNING status, encrypted Kinesis stream and checkpoint/commit logs.
3. Publish the bounded dataset; show the saved acknowledgement receipt.
4. Show Athena query ID and reconciliation: expected_count=actual_count=1,030, distinct_business_keys=1,030, duplicate/missing/unexpected rows=0, matches=true.
5. Show the stopped application and empty main stack after teardown. Explain retained bootstrap state, the budget's delayed nature, and the append-only rerun limitation.

Capture a real screen recording or command transcript during the actual run. Do not present this script or mocked output as a completed video/demo.

## Stop, purge and destroy

Stop ingestion first, wait for the final successful Athena reconciliation, then stop Flink. Keep the manifest, query IDs and verification JSON outside the bucket being destroyed.

```bash
.venv/bin/clickstream --profile clickstream stop
# Get the exact bucket from terraform output; confirm the account/region.
AWS_PROFILE=clickstream terraform -chdir=infra output -raw lake_bucket
# Replace the placeholder with that exact demo lake bucket in BOTH arguments.
.venv/bin/clickstream --profile clickstream purge-demo --bucket EXACT_DEMO_LAKE_BUCKET --confirm-bucket EXACT_DEMO_LAKE_BUCKET
AWS_PROFILE=clickstream terraform -chdir=infra plan -destroy -out=cleanup.tfplan
# Review: only the main demo stack, never bootstrap/state storage.
AWS_PROFILE=clickstream terraform -chdir=infra apply cleanup.tfplan
AWS_PROFILE=clickstream terraform -chdir=infra state list
```

Purge refuses a different account/region/project bucket, a versioned bucket or an app that is not READY. It deletes the named demo Glue table and demo objects only after exact bucket confirmation. This is destructive. Do not run it against shared data. Never clear an Iceberg prefix while the job is RUNNING. Verify application, stream, table/database, workgroup, lake and test roles absent through AWS APIs after destroy; retain bootstrap state storage.

If startup fails, inspect the existing application log stream. If stop times out, inspect status before using a force-stop recovery; do not leave billable compute unattended. If Athena diverges, preserve evidence and stop the app before investigating; do not hide mismatches by counting distinct IDs alone.

## Official references

- [Managed Flink 1.20 runtime](https://docs.aws.amazon.com/managed-flink/latest/java/flink-1-20.html)
- [Kinesis source](https://docs.aws.amazon.com/managed-flink/latest/java/how-sources.html)
- [Iceberg streaming writes](https://iceberg.apache.org/docs/1.10.0/flink-writes/)
- [Athena Iceberg support](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg.html)
