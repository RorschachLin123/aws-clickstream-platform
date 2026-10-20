# First cloud startup: missing Iceberg AWS SDK modules

On October 19, 2026, Terraform created all 21 resources successfully, but the first Managed Flink job startup failed before publication. CloudWatch reported `NoClassDefFoundError: software/amazon/awssdk/services/kms/model/EncryptionAlgorithmSpec` from `AwsProperties` during GlueCatalog initialization. The service returned the application to READY. No events had been published.

The dependency list included Glue, S3 and STS but omitted KMS and DynamoDB classes referenced by Iceberg's default AWS client factory. Both modules are now included under the existing AWS SDK 2.33.0 BOM. This changes packaging only; it does not grant KMS or DynamoDB API permissions. A regression test constructs the actual Iceberg AWS factory and its Glue/S3 clients without network requests. All four Java tests and the shaded build pass.

Terraform replaced only the content-addressed JAR and updated the same stopped application in place. The original startup error is preserved in local execution evidence. Cloud verification and cleanup are recorded separately in `v01-acceptance.md`.

Reference: [Iceberg 1.10.0 default AWS client factory](https://github.com/apache/iceberg/blob/apache-iceberg-1.10.0/aws/src/main/java/org/apache/iceberg/aws/AwsClientFactories.java).

The second startup reached Glue table initialization, then exposed missing source type information: Flink could not infer `KinesisStreamsSource<T>` after erasure. The source now passes `Types.STRING` to `fromSource`. A source-to-validation graph test reproduces that exact construction without contacting AWS. `flink-connector-base` is explicitly provided for local testing, as it is supplied by the managed runtime. All five Java tests and the rebuilt JAR pass. The application was stopped before replacement; no producer publication occurred during either failed startup.
