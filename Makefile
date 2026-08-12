.PHONY: help install rename check lint format typecheck test fix clean

# Keep the environment out of the source tree at a deterministic per-directory
# path, so every non-interactive caller (make, scripts, nohup'd subshells, CI)
# resolves the SAME env instead of building a second, extras-less .venv in-tree
# that uv then prefers. The symptom that motivates this is baffling: `uv run`
# finds an optional extra interactively and not under nohup. An inherited
# UV_PROJECT_ENVIRONMENT (e.g. a nix shell pinning the env to its closure)
# always wins. The hash keys on the absolute path so same-named checkouts
# (clones, worktrees) never share an env; if neither hash tool exists, fail
# loudly rather than silently collapsing them onto one.
ifeq ($(origin UV_PROJECT_ENVIRONMENT), undefined)
UV_ENV_HASH := $(shell printf '%s' "$(CURDIR)" | { command -v shasum >/dev/null 2>&1 && shasum || sha1sum; } | cut -c1-8)
$(if $(UV_ENV_HASH),,$(error cannot hash CURDIR: install shasum or sha1sum))
export UV_PROJECT_ENVIRONMENT := $(HOME)/.cache/uv-venvs/$(notdir $(CURDIR))-$(UV_ENV_HASH)
endif

help: ## show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-12s\033[0m %s\n", $$1, $$2}'

install: ## uv sync (install all deps including dev)
	uv sync

rename: ## rename package myproject -> NEW (usage: make rename NEW=your_pkg_name)
	uv run scripts/rename.py "$(NEW)"

check: lint typecheck test ## full inner loop (CI runs this)

fix: ## autofix lint + format, then run full check
	uv run ruff check --fix src tests
	uv run ruff format src tests
	$(MAKE) check

lint: ## ruff check (no fix) + format --check
	uv run ruff check src tests
	uv run ruff format --check src tests

format: ## ruff format (writes)
	uv run ruff format src tests

typecheck: ## basedpyright strict
	uv run basedpyright src tests

test: ## pytest
	uv run pytest

clean: ## remove caches
	rm -rf .pytest_cache .ruff_cache .basedpyright .hypothesis .coverage htmlcov dist build
	find . -type d -name __pycache__ -exec rm -rf {} +
