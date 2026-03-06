SHELL := /bin/bash

.PHONY: setup lint link-check dev push

setup:
	@echo "[setup] Initialize documentation tooling"
	@echo "- Install markdownlint-cli and lychee if needed"
	@echo "  npm i -g markdownlint-cli || true"
	@echo "  cargo install lychee || true"

lint:
	@if command -v markdownlint >/dev/null 2>&1; then \
		markdownlint "**/*.md"; \
	else \
		echo "markdownlint not found. Run: make setup"; \
		exit 1; \
	fi

link-check:
	@if command -v lychee >/dev/null 2>&1; then \
		lychee --no-progress "**/*.md"; \
	else \
		echo "lychee not found. Run: make setup"; \
		exit 1; \
	fi

dev:
	@echo "No preview server configured yet."
	@echo "Use your preferred docs viewer/editor."

push:
	@./scripts/git-quick-push.sh
