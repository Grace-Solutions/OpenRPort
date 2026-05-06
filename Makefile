.PHONY: help setup subtrees update-subtrees generate-config fetch-binaries build-agent agent-binaries prepare build up down test lint validate-env

SHELL := /bin/bash

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: prepare ## Full first-time setup (validate env, fetch binaries, generate config)

validate-env: ## Validate required environment variables
	@bash scripts/ValidateEnv.sh

generate-config: validate-env ## Generate runtime config files from .env
	@bash scripts/GenerateConfig.sh

fetch-binaries: validate-env ## Download rport agent binaries from upstream releases
	@bash scripts/FetchAgentBinaries.sh

build-agent: validate-env ## Build rport agent from src/Server for all targets
	@bash scripts/BuildAgentBinaries.sh

agent-binaries: validate-env ## Build or fetch agent binaries (per RPORT_AGENT_SOURCE)
	@bash scripts/MaterializeAgentBinaries.sh

prepare: validate-env generate-config agent-binaries ## Validate env, write configs, materialize agent binaries

subtrees: ## Add all git subtrees (first time only)
	@bash scripts/AddSubtrees.sh

update-subtrees: ## Pull latest from all upstream subtrees
	@bash scripts/UpdateSubtrees.sh

lint: ## Lint shell scripts (requires shellcheck)
	@which shellcheck >/dev/null 2>&1 || (echo "shellcheck not found - skipping"; exit 0)
	@shellcheck scripts/*.sh Container/*/entrypoint.sh || true

build: prepare ## Build all container images (after prepare)
	docker compose build

up: build ## Build and start all services
	docker compose up -d
	@echo "Services started. Run 'make test' to validate."

down: ## Stop all services
	docker compose down

test: ## Run the full test stack validation
	@bash scripts/TestStack.sh

logs: ## Tail logs from all services
	docker compose logs -f

status: ## Show service status
	docker compose ps

restart: ## Restart all services
	docker compose restart

clean: ## Stop services and remove volumes (DESTRUCTIVE)
	docker compose down -v
	@echo "All containers and volumes removed."
