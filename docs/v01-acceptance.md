# v0.1 acceptance

## Local evidence

- Fixed 500-journey fixture: 1,030 events, SHA-256 `3b8c43992a0985426ca6ccf86eb56d19a38a7c06851657078ddfddd47c635cbe`.
- 13 Python unit tests passed and cover deterministic generation, parent funnels, manifest tampering, content reconciliation, pagination and explicit/ambiguous Kinesis failures.
- 3 Java tests passed, including a real local Flink-to-Iceberg commit/read with exact business keys and integer amounts. The shaded Java 11 JAR builds successfully with AWS SDK dependencies aligned to 2.33.0.
- Both Terraform roots validate. Main 6 and bootstrap 5 mocked tests passed; plans cover opt-in provisioning, mandatory stream, fixed permissions boundary, constrained service trust, autoscaling off, Athena scan cap and Iceberg lifecycle protection.

## Live gates — pending

- [ ] Expanded IAM and fixed boundary reviewed and applied by administrator.
- [ ] Concrete paid-resource plan authorized and apply exits 0.
- [ ] Managed Flink application RUNNING; checkpoint and Iceberg commits observed.
- [ ] Producer manifest and acknowledgement receipt saved.
- [ ] Athena exact reconciliation matches every expected row and business key; query IDs/scanned bytes saved.
- [ ] Real demo recording/transcript captured.
- [ ] App stopped, demo data purged with explicit exact bucket confirmation, main stack destroyed.
- [ ] Independent inventory confirms resources absent; retained bootstrap documented.

Do not mark these gates based on a successful build, mocked provider or offline plan. Budget threshold execution and v0.2 failure recovery are outside this baseline's verified scope.
