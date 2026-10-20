# v0.1 acceptance

## Local evidence

- Fixed 500-journey fixture: 1,030 events, SHA-256 `3b8c43992a0985426ca6ccf86eb56d19a38a7c06851657078ddfddd47c635cbe`.
- 16 Python unit tests passed and cover deterministic generation, parent funnels, manifest tampering, content reconciliation, pagination and explicit/ambiguous Kinesis failures.
- 5 Java tests passed, including a real local Flink-to-Iceberg commit/read with exact business keys and integer amounts. The shaded Java 11 JAR builds successfully with AWS SDK dependencies aligned to 2.33.0.
- Both Terraform roots validate. Main 7 and bootstrap 5 mocked tests passed; plans cover opt-in provisioning, mandatory stream, fixed permissions boundary, constrained service trust, autoscaling off, Athena scan cap and Iceberg lifecycle protection.

## Live gates — pending

- [x] Expanded IAM and fixed boundary reviewed and applied by administrator (Oct 19, boundary default v3).
- [x] Concrete paid-resource plan authorized; real apply exits 0 with 21 additions, no changes or deletions.
- [x] Managed Flink version 3 reached RUNNING; 72 completed checkpoints observed.
- [ ] Data-bearing Iceberg commit and producer-to-Athena delivery verified.
- [ ] Producer manifest and acknowledgement receipt saved.
- [ ] Athena exact reconciliation matches every expected row and business key; query IDs/scanned bytes saved.
- [ ] Real demo recording/transcript captured.
- [x] App READY, dedicated table and 16 demo objects purged, remaining 20 main-stack resources destroyed.
- [x] Independent inventory confirms all demo resources absent; remote main state empty; versioned state bucket and CI/operator identities retained.

Do not mark these gates based on a successful build, mocked provider or offline plan. Budget threshold execution and v0.2 failure recovery are outside this baseline's verified scope.

## Runtime limit incident

The run exceeded its authorized window after a local execution/connection interruption prevented the local stop guard from working. The observed checkpoint span is 35.49 minutes; actual charged duration is not yet reconciled. No producer publication occurred. A cloud stop guard is prepared, tested locally and awaiting explicit authorization alongside a new bounded run. See [incident and corrective action](v01-runtime-incident.md). This phase is not accepted end to end.
