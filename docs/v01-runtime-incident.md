# Runtime deadline incident — October 19, 2026

The first two cloud startups failed before producer publication (see `v01-startup-failure.md`). The corrected application version 3 entered RUNNING and CloudWatch recorded 72 completed checkpoints, from 2026-10-20 02:21:31Z to 02:57:00Z. That checkpoint span alone is 35.49 minutes, exceeding the authorized 30-minute application runtime. No events were published and no Athena delivery claim is made.

A local process had an absolute stop deadline of 02:36Z. The controlling Mac experienced a long execution/connection interruption; both the application poller and stop guard failed with endpoint/DNS connection errors, including failure to refresh the AWS login token. The precise host/network cause is not established. The local guard did not provide independent protection. Once AWS connectivity was restored, the operator observed RUNNING and immediately requested force stop at approximately 02:57Z. READY was independently verified before cleanup. Cost is not yet reconciled against delayed billing; do not infer the charge from the console's earlier zero balance.

The dedicated Glue table and 16 demo objects were deleted, then Terraform destroyed 20 remaining resources successfully. Independent AWS APIs confirm application, stream, bucket, database/table, workgroup, logs, runtime roles, budget role/policy and budget absent. The main remote state is empty. The versioned state bucket and CI/operator identities remain.

## Corrective change prepared, not deployed

A one-shot EventBridge Scheduler target requests `StopApplication(Force=true)` for only the named demo app. Its execution role has only `kinesisanalytics:StopApplication` on that ARN and retains the project boundary. Trust is restricted to this account and the exact project schedule group. This operates in AWS independently of the Mac. Delivery is best effort, with three retries and a five-minute event age; it is not a guaranteed billing cap.

The CLI now refuses startup unless the cloud schedule is enabled, has the exact UTC stop-only target, no flexible time window, and a deadline 2–15 minutes in the future. Normal recording still stops the application in a finally block. A failed startup returning to READY now fails promptly instead of polling for 15 minutes.

The revised real plan is 25 additions: the same 21 resources plus a schedule group, bounded stop role, inline stop policy and one-shot schedule. Additional IAM access is restricted to these exact guard resources and PassRole to Scheduler. No new cloud resources or privileges have been applied. A new bounded paid run and this additional privilege scope need explicit authorization before execution.

Official references: [Scheduler universal targets](https://docs.aws.amazon.com/scheduler/latest/UserGuide/managing-targets-universal.html), [Scheduler confused deputy prevention](https://docs.aws.amazon.com/scheduler/latest/UserGuide/cross-service-confused-deputy-prevention.html), [Flink force stop](https://docs.aws.amazon.com/cli/latest/reference/kinesisanalyticsv2/stop-application.html).
