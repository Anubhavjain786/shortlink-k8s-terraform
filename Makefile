CLUSTER  := shortlink
IMAGE    := shortlink
TAG      ?= dev
TF_LOCAL := terraform -chdir=infra/local

.PHONY: help test build cluster load deploy up smoke load-test status destroy down validate

help: ## Show this help
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

test: ## Run lint and unit tests in a container
	docker run --rm -v "$(PWD)":/src -w /src python:3.12-slim sh -c \
	  "pip install -q --root-user-action=ignore -r requirements-dev.txt && ruff check app tests && python -m pytest -q"

build: ## Build the app image
	docker build -t $(IMAGE):$(TAG) .

cluster: ## Create the local kind cluster (idempotent)
	@kind get clusters | grep -qx $(CLUSTER) || kind create cluster --config kind/cluster.yaml --wait 180s

load: build ## Load the image into the kind nodes
	kind load docker-image $(IMAGE):$(TAG) --name $(CLUSTER)

deploy: ## Apply Terraform against the kind cluster
	$(TF_LOCAL) init -input=false
	$(TF_LOCAL) apply -input=false -auto-approve -var image_tag=$(TAG)

up: cluster load deploy smoke ## Everything: cluster, image, deploy, smoke test

smoke: ## Create a link and follow it
	./scripts/smoke.sh http://localhost:8080

load-test: ## Generate CPU load so the autoscaler adds pods
	kubectl -n shortlink run load --rm -i --restart=Never --image=busybox:1.36 -- \
	  sh -c 'end=$$(( $$(date +%s) + 120 )); while [ $$(date +%s) -lt $$end ]; do for i in 1 2 3 4 5 6 7 8; do wget -q -O- http://shortlink/healthz >/dev/null & done; wait; done'

status: ## Show pods, autoscaler and service
	kubectl -n shortlink get pods,hpa,svc,pdb -o wide

validate: ## Format check and validate all Terraform
	terraform fmt -check -recursive infra
	terraform -chdir=infra/local init -backend=false -input=false && terraform -chdir=infra/local validate
	terraform -chdir=infra/aws init -backend=false -input=false && terraform -chdir=infra/aws validate

destroy: ## Remove everything Terraform created in the cluster
	$(TF_LOCAL) destroy -input=false -auto-approve

down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)
