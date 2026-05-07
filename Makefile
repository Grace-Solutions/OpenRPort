.PHONY: help setup subtrees update-subtrees generate-config fetch-binaries build-agent agent-binaries prepare pull build build-up up down test lint validate-env logs status restart clean

SHELL := /bin/bash

# Compose file selection. compose.yaml is runtime-only (image refs);
# compose.build.yaml layers in the build: blocks for local development.
COMPOSE_RUN   := docker compose
COMPOSE_BUILD := docker compose -f compose.yaml -f compose.build.yaml

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

pull: ## Pull all images from the registry (per OPENRPORT_IMAGE_NAMESPACE/TAG)
	$(COMPOSE_RUN) pull

build: prepare ## Build all container images locally (compose.yaml + compose.build.yaml)
	$(COMPOSE_BUILD) build

build-up: build ## Build locally and start all services (no registry pull)
	$(COMPOSE_BUILD) up -d
	@echo "Services started from local build. Run 'make test' to validate."

up: prepare pull ## Pull from registry and start all services
	$(COMPOSE_RUN) up -d
	@echo "Services started from registry images. Run 'make test' to validate."

down: ## Stop all services
	$(COMPOSE_RUN) down

test: ## Run the full test stack validation
	@bash scripts/TestStack.sh

logs: ## Tail logs from all services
	$(COMPOSE_RUN) logs -f

status: ## Show service status
	$(COMPOSE_RUN) ps

restart: ## Restart all services
	$(COMPOSE_RUN) restart

clean: ## Stop services and remove volumes (DESTRUCTIVE)
	$(COMPOSE_RUN) down -v
	@echo "All containers and volumes removed."
