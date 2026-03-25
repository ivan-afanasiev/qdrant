SHELL := /bin/bash
.DEFAULT_GOAL := help

SCRIPT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
WORKSPACE_ROOT := $(abspath $(SCRIPT_DIR)/../../..)
XCFRAMEWORK := $(SCRIPT_DIR)out/QdrantEdge.xcframework

# ── Setup ────────────────────────────────────────────────────────────────────

.PHONY: setup
setup: setup-homebrew setup-rust setup-targets ## Install all prerequisites

.PHONY: setup-homebrew
setup-homebrew: ## Install Homebrew dependencies (protobuf)
	@command -v brew >/dev/null 2>&1 || { echo "Homebrew not found. Install from https://brew.sh"; exit 1; }
	brew install protobuf

.PHONY: setup-rust
setup-rust: ## Install Rust toolchain via rustup
	@if ! command -v rustup >/dev/null 2>&1; then \
		echo "Installing rustup..."; \
		curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; \
		echo 'source "$$HOME/.cargo/env"' >> ~/.zshrc; \
	fi
	@echo "Rust toolchain OK: $$(rustc --version 2>/dev/null || echo 'restart shell to activate')"

.PHONY: setup-targets
setup-targets: ## Install required Rust cross-compilation targets
	rustup target add \
		aarch64-apple-ios \
		aarch64-apple-ios-sim \
		x86_64-apple-ios \
		aarch64-apple-darwin \
		x86_64-apple-darwin \
		aarch64-apple-tvos \
		aarch64-apple-tvos-sim \
		x86_64-apple-tvos \
		aarch64-apple-visionos \
		aarch64-apple-visionos-sim

# ── Build ────────────────────────────────────────────────────────────────────

.PHONY: build
build: ## Build the XCFramework (release)
	@bash $(SCRIPT_DIR)build-xcframework.sh

.PHONY: build-debug
build-debug: ## Build the XCFramework (debug, faster compile)
	@bash $(SCRIPT_DIR)build-xcframework.sh --debug

# ── Info ─────────────────────────────────────────────────────────────────────

.PHONY: size
size: ## Show XCFramework size breakdown
	@if [ ! -d "$(XCFRAMEWORK)" ]; then \
		echo "XCFramework not found. Run 'make build' first."; exit 1; \
	fi
	@echo "=== XCFramework total ==="
	@du -sh "$(XCFRAMEWORK)"
	@echo ""
	@echo "=== Per-platform static library sizes ==="
	@find "$(XCFRAMEWORK)" -name '*.a' -exec sh -c 'echo "$$(du -sh "$$1" | cut -f1)\t$$(basename $$(dirname $$(dirname "$$1")))"' _ {} \;
	@echo ""
	@echo "=== Architecture details ==="
	@find "$(XCFRAMEWORK)" -name '*.a' | while read lib; do \
		echo "--- $$(basename $$(dirname $$(dirname "$$lib"))) ---"; \
		lipo -info "$$lib"; \
	done

# ── Clean ────────────────────────────────────────────────────────────────────

.PHONY: clean
clean: ## Remove build outputs
	rm -rf $(SCRIPT_DIR)out

# ── Help ─────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
