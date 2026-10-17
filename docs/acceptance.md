# v0.0.1 acceptance evidence

Implementation status and verification results belong here. Do not mark cloud acceptance based on offline validation.

## Local checks

Verified locally on 2026-10-07:

- Terraform 1.13.5; AWS provider 6.67.0; random provider 3.9.1.
- `make check`: exit 0; fmt and both validate checks pass.
- Mocked Terraform tests: bootstrap 5 passed, main 3 passed; no AWS API calls/resources.
- Gitleaks 8.24.2 source scan: exit 0, no leaks found (excludes provider caches/Git metadata).
- macOS ARM64 and Linux AMD64 provider checksums recorded in both lockfiles.
- Git ignore checks cover both states, local tfvars and backend configuration.
- Make plan/apply/destroy/nuke commands inspected with `make -n`; no cloud commands executed.
- GitHub Actions dependencies pinned to verified commit SHAs.
- Actionlint 1.7.7 workflow validation: exit 0 (shellcheck is not installed).
- Git history secret scan after initial commit: exit 0, no leaks found.
- 24 source files tracked; no state, local config or provider cache files tracked.

These checks do not prove cloud IAM permissions, action execution, deployment success or service costs.

## Cloud and publication gates

- [x] Correct account/region verified with STS.
- [x] Bootstrap apply exit 0; private encrypted/versioned state and exact main OIDC trust inspected.
- [ ] enable_stream=true main apply exit 0; stream/lake/catalog/logs/budget/action exist.
- [ ] Budget policy and target-role scope inspected; action behavior tested with method documented.
- [ ] PR checks green; main/manual OIDC identity + read-only plan green.
- [ ] Secret scan clean and `git ls-files` contains no state or local tfvars.
- [ ] Main destroy exit 0; cloud inventory confirms demo resources absent; retained bootstrap resources documented.
- [ ] README diagram and reproducible runbook verified by a fresh checkout.
- [ ] Public v0.0.1 release identifies infrastructure skeleton and its actual limitations.

## Evidence to capture

Record UTC timestamp, git revision, commands/exit codes, AWS inventory, CI links and Budget Action status. Redact credentials, session tokens and personal email. Account ID and bucket names may also be redacted before publication. No cloud screenshots, billing evidence or demo video have been created yet.

## 2026-10-16 IAM deployment preparation

Mandatory root-managed boundary added to all three Terraform-created roles. Both validate checks and all 8 mocked tests pass, including boundary assertions. CI accepts PROJECT_PERMISSIONS_BOUNDARY_ARN. Operator trust/permissions/boundary review artifacts were prepared outside Git. Operator role and boundary were subsequently created on 2026-10-16 after explicit user approval; see the next entry. No data-stack resources exist yet.

## 2026-10-16 operator authorization

User explicitly confirmed the IAM grant. Console verifies ClickstreamProjectBoundary exists; ClickstreamOperator has the fixed boundary, ClickstreamDeploySkeleton inline policy, a one-hour session limit, and an exact trust to haolin-dev. Local clickstream profile uses a credential_process bridge from clickstream-login.

GitHub REST API confirms repository RorschachLin123/aws-clickstream-platform, repository ID 1414166401, owner ID 334108539, immutable OIDC subject enabled, and default branch main. Ignored local bootstrap variables use the exact subject prefix plus ref:refs/heads/main.

At the end of this preparation step, STS validation was blocked by an expired login cache; the next entry records its resolution and actual deployments.

## 2026-10-17 live deployment verification (UTC)

- STS verified the intended account and assumed ClickstreamOperator deployment role.
- Bootstrap init/plan/apply exited 0: 9 resources added. S3 versioning Enabled, AES256 encryption and all four public-access blocks verified through AWS APIs. CI role boundary and exact immutable main-branch OIDC subject verified through GetRole.
- Main init/plan/apply with enable_stream=false exited 0: 14 resources added. Monthly account-wide budget verified at USD 30. Budget Action verified AUTOMATIC/STANDBY, 100% threshold, targeting only the project producer role with the named deny-input policy. Actual threshold execution was not tested.
- A separate plan with enable_stream=true proposed one stream. Apply failed at CreateStream with SubscriptionRequiredException (request ID dbd97a81-dec4-9014-b894-5ba10d18a3fc). No successful Kinesis creation or data flow is claimed. Account service eligibility/activation must be resolved before repeating this acceptance step; do not broaden IAM based on this error.
- GitHub authentication verified through the macOS keyring. The restricted shell could not access the keyring and initially reported a misleading invalid-token result. IAM-boundary commit bfa36ae was pushed. Repository CI variables and BUDGET_EMAIL secret are configured; ENABLE_STREAM=false. Main workflow checks and the real AWS OIDC plan both passed: https://github.com/RorschachLin123/aws-clickstream-platform/actions/runs/39013423488 . The plan does not apply changes.
- Main cleanup from a reviewed 14-resource destroy plan removed 13 resources, then exited 1 on Glue DeleteDatabase: missing descendant table scope (request ID 0ae67ba1-8fe8-498f-a536-e5d6e40d9c00). Only clickstream_dev remains in main state. A narrowly scoped correction for DeleteDatabase on this database's table/* and userDefinedFunction/* descendants was explicitly approved and applied to the operator inline policy and root-managed boundary. The subsequent saved destroy plan deleted the remaining database successfully (exit 0). Existing live policy records were not overwritten. See AWS Glue resource ARN documentation for descendant permission requirements.

Retained bootstrap resources are intentional: encrypted/versioned state bucket, GitHub OIDC provider, and bounded read-only CI role. The separately approved operator role and root-managed boundary are retained. Bootstrap state is local and ignored by Git. No credentials, state, local tfvars or saved plans are tracked.


### Reproduction note: Glue database deletion

When scoping glue:DeleteDatabase, AWS requires the catalog/database ARNs and both descendant scopes table/clickstream_dev/* and userDefinedFunction/clickstream_dev/*, even for this empty skeleton database. Keep the additional action limited to DeleteDatabase and to the named project database. See https://docs.aws.amazon.com/glue/latest/dg/glue-specifying-resource-arns.html .


### Final cleanup and PR checks

After the user restored the administrator console session, the two approved policy documents were saved successfully. The boundary now has a second version. A fresh destroy plan proposed exactly one deletion; apply exited 0 and deleted clickstream_dev. Main state contains no resources; Glue GetDatabase returns EntityNotFoundException.

PR #1 checks passed: https://github.com/RorschachLin123/aws-clickstream-platform/pull/1 . The PR plan job is intentionally skipped; AWS OIDC plan is restricted to main. Main workflow real plan and checks previously passed at bfa36ae. Kinesis creation and budget threshold execution remain unverified, so full skeleton release acceptance is still pending.
