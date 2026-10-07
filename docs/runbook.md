# Deployment and teardown runbook

## Configuration

1. Authenticate locally through AWS SSO or another short-lived mechanism; confirm the account with `aws sts get-caller-identity`. No AWS CLI/credentials were configured during skeleton creation.
2. Create a GitHub repository and inspect its OIDC subject format. New/renamed repositories may use immutable owner/repository IDs. Supply the exact `repo:…:ref:refs/heads/main` subject; do not use a wildcard or a PR subject. This workflow does not reference a GitHub Environment, which would change the subject.
3. Fill both ignored tfvars files from their examples. Bootstrap and main must use identical project/env/region/owner settings. CI currently uses default project `clickstream` / env `dev`, and state key `clickstream/dev/terraform.tfstate`; coordinate edits if changing these names.
4. `producer_principal_arn` is an existing IAM role, not the STS assumed-role session ARN. This is the only identity trusted by the producer role; the caller also needs permission to assume it. Account deployment permissions must include IAM, S3, Kinesis, Glue, Logs, Budgets and scoped `iam:PassRole` to Budgets. Use your existing operator profile rather than adding a broad deployment role to GitHub.
5. If the account has GitHub's OIDC provider already, supply `existing_oidc_provider_arn`; AWS will reject a duplicate provider URL.

## Bootstrap and first apply

```bash
make bootstrap-init
make bootstrap-plan
make bootstrap-apply
terraform -chdir=infra/bootstrap output
```

Back up local bootstrap state outside Git. Fill `infra/backend.tfbackend` from state_bucket output, then `make init`, `make plan`, review, and `make apply`. By default no Kinesis stream exists. Set `enable_stream=true` for full skeleton acceptance, repeat plan/apply, and start a teardown timer before the session. Local saved plans are ignored and deleted after apply/destroy; regenerate them whenever configuration changes.

## GitHub setup

Repository variables:

| Variable | Value |
| --- | --- |
| AWS_PLAN_ROLE_ARN | Bootstrap `ci_role_arn` output |
| AWS_REGION | Same region as both tfvars |
| TF_STATE_BUCKET | Bootstrap `state_bucket` output |
| PRODUCER_PRINCIPAL_ARN | Existing operator IAM role ARN |
| ENABLE_STREAM | `true` during active demo; `false` otherwise |

Repository secret: `BUDGET_EMAIL`. No access key secrets. Main branch protection should require the `checks` job; `plan` is intentionally skipped on PRs. Main push/manual dispatch generates a read-only cloud plan once AWS_PLAN_ROLE_ARN is configured. Missing configuration is not evidence of successful OIDC. Set ENABLE_STREAM to match local state/config before interpreting a plan.

Plan artifacts contain account/resource metadata and notification email, even though they contain no credentials by design. Review before sharing externally. Artifacts expire after three days. Provider lockfiles include Linux and macOS hashes; keep them tracked.

## Budget action and recovery

The $30 budget covers the whole account; adjust if other workloads exist. Alerts use actual spend and may lag usage. At 100%, the deny policy stops writes only through the project producer role. Kinesis, Flink and other resources continue billing until deleted/stopped. Do not wait for an alert to end a demo. The action is automatic; to test its policy without spending $30, use IAM simulation/manual controlled invocation and record exactly what was tested. Reset/reverse the action through AWS Budgets when resuming a demo after it has fired; never detach controls merely to keep spending.

If Budgets attached the policy, Terraform may need it detached before deleting the producer role. Inspect the Budget Action status, reverse/reset the action, then rerun destroy. Record a real teardown failure and repair rather than hiding it.

## Teardown

```bash
make destroy
# Only if nonempty lake blocks destroy, and its contents are disposable:
make nuke
terraform -chdir=infra state list
```

Verify the named Kinesis stream, lake, Glue database, CloudWatch log group, demo IAM roles/policy and budget/action are absent in AWS. An empty Terraform state alone is not a cloud inventory check. Bootstrap state bucket, CI role/policy and managed OIDC provider intentionally remain; list these retained resources in evidence. The state bucket incurs small storage costs. Full account cleanup requires a separate explicit review of bootstrap state/dependencies; do not erase the remote state bucket while the main stack still exists.

## Common failures

- AccessDenied on OIDC: exact subject/audience mismatch, main-vs-PR/environment mismatch, immutable repository ID, or credentials role variable wrong.
- CI plan AccessDenied after validate passes: provider schema validation cannot prove IAM permissions; inspect the denied read API and scope the CI role before retrying.
- Duplicate provider: reuse existing OIDC provider ARN.
- Lake name already exists: deterministic account/region name can collide with a prior stack; import owned resources or choose coordinated project/env settings.
- Budget action creation denied: verify local operator's scoped PassRole and Budgets execution-role IAM attachment permissions.
- Destroy fails with nonempty bucket: inspect contents, use the explicitly confirmed nuke for disposable data.
