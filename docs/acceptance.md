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
