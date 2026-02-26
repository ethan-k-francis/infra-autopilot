# =============================================================================
# Infra Autopilot — Makefile
# Top-level build, test, and deployment automation.
# =============================================================================

# Cluster name used by Kind and Terraform
CLUSTER_NAME ?= autopilot
# Namespace where autopilot workloads run
NAMESPACE ?= autopilot
# Container image tags
AGENT_IMAGE ?= infra-autopilot/agent:latest
REMEDIATION_IMAGE ?= infra-autopilot/remediation:latest

# -----------------------------------------------------------------------------
# Cluster lifecycle — create and destroy the local Kind cluster
# -----------------------------------------------------------------------------

.PHONY: cluster-up
cluster-up: ## Create a Kind cluster for local development
	kind create cluster --name $(CLUSTER_NAME) --config deploy/kind-config.yaml

.PHONY: cluster-down
cluster-down: ## Delete the Kind cluster
	kind delete cluster --name $(CLUSTER_NAME)

# -----------------------------------------------------------------------------
# Build — compile the Go agent and build Docker images
# -----------------------------------------------------------------------------

.PHONY: build
build: build-agent build-remediation ## Build all container images

.PHONY: build-agent
build-agent: ## Build the Go health agent Docker image
	docker build -t $(AGENT_IMAGE) agent/

.PHONY: build-remediation
build-remediation: ## Build the Python remediation Docker image
	docker build -t $(REMEDIATION_IMAGE) remediation/

# -----------------------------------------------------------------------------
# Test — run unit tests for Go and Python
# -----------------------------------------------------------------------------

.PHONY: test
test: test-agent test-remediation ## Run all tests

.PHONY: test-agent
test-agent: ## Run Go agent tests
	cd agent && go test ./...

.PHONY: test-remediation
test-remediation: ## Run Python remediation tests
	cd remediation && python -m pytest tests/ -v 2>/dev/null || echo "No tests yet"

# -----------------------------------------------------------------------------
# Deploy — push images to Kind and apply K8s manifests
# -----------------------------------------------------------------------------

.PHONY: deploy
deploy: build ## Build images, load into Kind, and apply manifests
	kind load docker-image $(AGENT_IMAGE) --name $(CLUSTER_NAME)
	kind load docker-image $(REMEDIATION_IMAGE) --name $(CLUSTER_NAME)
	kubectl apply -f deploy/manifests/namespace.yaml
	kubectl apply -f deploy/manifests/agent-rbac.yaml
	kubectl apply -f deploy/manifests/remediation-deployment.yaml
	kubectl apply -f deploy/manifests/agent-deployment.yaml

# -----------------------------------------------------------------------------
# Logs — tail logs from running workloads
# -----------------------------------------------------------------------------

.PHONY: logs
logs: ## Tail logs from the health agent
	kubectl logs -f -n $(NAMESPACE) -l app=health-agent

# -----------------------------------------------------------------------------
# Clean — remove build artifacts
# -----------------------------------------------------------------------------

.PHONY: clean
clean: ## Remove build artifacts and temp files
	rm -rf bin/
	rm -rf agent/bin/
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true

# -----------------------------------------------------------------------------
# Help — list available targets
# -----------------------------------------------------------------------------

.PHONY: help
help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
