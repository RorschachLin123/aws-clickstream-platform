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

## Cloud and publication gates — all pending

- [ ] Correct account/region verified with STS.
- [ ] Bootstrap apply exit 0; private encrypted/versioned state and exact main OIDC trust inspected.
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

STS AssumeRole validation remains blocked by an expired local login cache (last updated 2026-10-13 UTC). This is separate from the root console session. No bootstrap/main apply or destroy has been executed.
