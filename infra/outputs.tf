output "lake_bucket" { value = aws_s3_bucket.lake.id }
output "glue_database" { value = aws_glue_catalog_database.clickstream.name }
output "stream_name" { value = try(aws_kinesis_stream.events[0].name, null) }
output "producer_role_arn" { value = aws_iam_role.producer.arn }
output "budget_name" { value = aws_budgets_budget.monthly.name }
