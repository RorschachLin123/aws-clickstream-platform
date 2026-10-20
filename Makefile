SHELL := /bin/bash
TF ?= terraform
AWS ?= aws
INFRA := infra
PYTHON ?= python3
MVN ?= mvn

.PHONY: app-check app-build
app-check:
	PYTHONPATH=src $(PYTHON) -m unittest discover -s tests -v
	$(MVN) -B -f flink/pom.xml verify
app-build:
	$(MVN) -B -f flink/pom.xml package

.PHONY: help fmt check validate bootstrap-init bootstrap-plan bootstrap-apply init plan apply destroy nuke
help:
	@echo 'Bootstrap: make bootstrap-init bootstrap-plan bootstrap-apply'
	@echo 'Stack: make init plan apply destroy; check: make check'
	@echo 'nuke deletes lake data only after explicit bucket-name confirmation.'
fmt:
	$(TF) fmt -recursive infra
check:
	$(TF) fmt -check -recursive infra
	$(TF) -chdir=infra/bootstrap init -backend=false -input=false
	$(TF) -chdir=infra/bootstrap validate
	$(TF) -chdir=infra init -backend=false -input=false
	$(TF) -chdir=infra validate
	$(TF) -chdir=infra/bootstrap test
	$(TF) -chdir=infra test
validate:
	$(TF) -chdir=infra/bootstrap validate
	$(TF) -chdir=infra validate
bootstrap-init:
	$(TF) -chdir=infra/bootstrap init
bootstrap-plan:
	$(TF) -chdir=infra/bootstrap plan
bootstrap-apply:
	$(TF) -chdir=infra/bootstrap apply
init:
	$(TF) -chdir=infra init -reconfigure -backend-config=backend.tfbackend
plan:
	$(TF) -chdir=infra plan -out=deployment.tfplan
apply:
	@test -f infra/deployment.tfplan || (echo 'Run make plan and review it first.'; exit 1)
	@read -r -p 'Type APPLY to apply the reviewed plan: ' answer; test "$$answer" = APPLY
	$(TF) -chdir=infra apply deployment.tfplan
	rm -f infra/deployment.tfplan
destroy:
	$(TF) -chdir=infra destroy
	rm -f infra/deployment.tfplan
nuke:
	@set -euo pipefail; bucket="$$($(TF) -chdir=infra output -raw lake_bucket)"; \
	read -r -p "Permanently delete lake objects? Type $$bucket: " answer; \
	test "$$answer" = "$$bucket"; \
	$(AWS) s3 rm "s3://$$bucket" --recursive; \
	$(TF) -chdir=infra destroy; \
	rm -f infra/deployment.tfplan
