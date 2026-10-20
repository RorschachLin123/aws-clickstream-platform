# v0.1 acceptance evidence

The data path is verified on AWS. One empty Scheduler group remains pending administrator cleanup; this is not yet a fully completed teardown or release.

## Real end-to-end result — October 20, 2026

| Check | Observed result |
|---|---:|
| Producer acknowledged | 1,030 |
| Manifest expected rows | 1,030 |
| Athena actual rows | 1,030 |
| Distinct event business keys within the run | 1,030 |
| Duplicate keys / missing rows / unexpected rows | 0 / 0 / 0 |
| All nine event fields match | true |
| Final query scanned bytes | 38,197 |

Run ID `v01-seed42`, seed 42, 500 journeys: 500 impressions, 280 clicks, 127 installs, 103 activations and 20 payments. Manifest SHA-256: `3b8c43992a0985426ca6ccf86eb56d19a38a7c06851657078ddfddd47c635cbe`.

Final Athena query: `3874c2f1-25d1-4fe0-a30e-a66848703877`, in engine-3 workgroup `clickstream-dev-demo`, with an enforced 10 MiB scan cap. The verifier fetched all rows and compared Counters of every field, including integer cents; a matching aggregate count alone was not sufficient.

Glue-backed Iceberg v2 snapshot `521654914812465959` reports checkpoint 2, 1,030 added/total records, one Parquet data file and Flink runtime 1.20.5. Actual JSON metadata, query IDs/results, acknowledgement and real command captures are retained locally outside Git.

## Observed recovery and fixes

The initial producer publication succeeded once. Athena then failed to validate its result bucket because the operator lacked `s3:GetBucketLocation`. The recorder stopped Flink in finally before a data-bearing checkpoint; metadata had no snapshot and a preflight Athena query later returned zero rows. The lake policy now grants only this region-metadata read to the exact existing operator role, under its unchanged boundary. No new object access or IAM identity grant was added.

Recovery restarted the same job under a six-minute AWS stop deadline and read the retained Kinesis records. Reconcile-only recording validated the original acknowledgement and skipped publication. Seven reconciliation queries progressed from zero rows to the exact match above. Normal finally stop completed READY. This verifies this recovery path; it does not establish a general exactly-once/deduplication guarantee. Deliberate producer reruns remain unsafe for the append-only baseline.

The independent cloud schedule was deployed and verified before startup. Successful timed force-stop was not exercised because normal stop completed first. Scheduler is best effort, not a hard billing cap. The earlier local-runtime overrun remains documented in [the incident report](v01-runtime-incident.md); no final billing amount has been verified.

## Validation and cleanup

- 17 Python tests pass, including deterministic generation, exact reconciliation, ambiguous-send protection and reconcile-only recording never publishing.
- 5 Java tests pass, including local Flink/Iceberg write/read, AWS client initialization and the Kinesis source graph.
- 7 main and 5 bootstrap mocked Terraform tests pass. Terraform validate and format checks pass.
- Original 21-resource apply and later 25-resource guarded apply succeeded. PR CI runs offline checks; main-only OIDC cloud planning was established by the skeleton. No automatic apply is configured.
- [x] Producer acknowledgement, full Athena verification and data-bearing snapshot preserved.
- [x] Actual command recording preserved; application stopped to READY before purge.
- [x] Dedicated table and 22 demo objects purged; Flink, Kinesis, Athena workgroup, lake, logs, runtime/budget roles and policy deleted and independently checked.
- [ ] Delete final empty Scheduler group and verify remote main state empty. AWS group deletion needs `DeleteSchedule` on the exact project group wildcard in addition to `DeleteScheduleGroup`; minimal administrator correction is prepared.
- [x] Versioned state storage and CI/operator identities retained.

The dedicated Athena workgroup permits recursive deletion of its test query history. Its query evidence is copied locally before teardown. Neither bootstrap state history nor shared data is purged. Release publication and LinkedIn posting are separate from this verification.
