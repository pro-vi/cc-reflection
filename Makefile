# Makefile for cc-reflection
#
# WHY: Standardized commands for common development tasks
# USAGE: make test, make test-unit, make install, etc.

.PHONY: help test test-unit test-integration test-contracts test-env test-watch install uninstall verify clean update-golden eval-score eval-score-all eval-summary eval-list eval-run eval-run-all eval-blind

# Default target
help:
	@echo "CC-Reflection Development Commands"
	@echo "=================================="
	@echo ""
	@echo "Testing:"
	@echo "  make test               Run all tests (unit + integration)"
	@echo "  make test-unit          Run unit tests only"
	@echo "  make test-integration   Run integration tests only"
	@echo "  make test-contracts     Run cross-language contract tests"
	@echo "  make test-env           Run environment variable tests"
	@echo "  make test-watch         Run tests in watch mode (requires entr)"
	@echo ""
	@echo "Installation:"
	@echo "  make install          Install cc-reflection"
	@echo "  make uninstall        Remove installation"
	@echo "  make verify           Verify installation"
	@echo ""
	@echo "Development:"
	@echo "  make format           Format shell scripts with shfmt"
	@echo "  make lint             Lint shell scripts with shellcheck"
	@echo "  make update-golden    Update golden test baselines"
	@echo "  make logs             Tail reflection logs"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean            Remove temporary files and logs"
	@echo "  make clean-seeds      Remove test reflection seeds"
	@echo ""

# ============================================================================
# TESTING
# ============================================================================

test:
	@echo "Running all tests..."
	@./tests/run_all_tests.sh all

test-unit:
	@echo "Running unit tests..."
	@./tests/run_all_tests.sh unit

test-integration:
	@echo "Running integration tests..."
	@./tests/run_all_tests.sh integration

test-contracts:
	@echo "Running cross-language contract tests..."
	@if command -v bats &>/dev/null; then \
		bats tests/integration/test_contracts.bats; \
	else \
		./tests/bats/bin/bats tests/integration/test_contracts.bats; \
	fi

test-env:
	@echo "Running environment variable contract tests..."
	@if command -v bats &>/dev/null; then \
		bats tests/unit/test_env_vars.bats; \
	else \
		./tests/bats/bin/bats tests/unit/test_env_vars.bats; \
	fi

test-watch:
	@echo "Running tests in watch mode (Ctrl+C to exit)..."
	@echo "Watching: lib/*.sh, lib/*.ts, bin/*"
	@if command -v entr &>/dev/null; then \
		find lib bin tests -type f | entr -c make test; \
	else \
		echo "Error: entr not found"; \
		echo "Install: brew install entr"; \
		exit 1; \
	fi

# ============================================================================
# INSTALLATION
# ============================================================================

install:
	@./install.sh

uninstall:
	@./install.sh uninstall

check:
	@./install.sh check

verify: check

# ============================================================================
# CLEANUP
# ============================================================================

clean:
	@echo "Cleaning temporary files..."
	@rm -f /tmp/cc-*.log 2>/dev/null || true
	@rm -rf ~/.claude/reflections/tmp/* 2>/dev/null || true
	@echo "✓ Temporary files cleaned"

clean-seeds:
	@echo "Warning: This will remove ALL reflection seeds!"
	@read -p "Are you sure? (y/N) " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		rm -rf ~/.claude/reflections/seeds/*; \
		echo "✓ Reflection seeds cleaned"; \
	else \
		echo "Cancelled"; \
	fi

clean-all: clean clean-seeds
	@rm -rf ~/.claude/reflections/logs/* 2>/dev/null || true
	@echo "✓ All cc-reflection data cleaned"

# ============================================================================
# DEVELOPMENT
# ============================================================================

# Format shell scripts (if shfmt is installed)
# NOTE: bin/cc-* pattern excludes .ts files
format:
	@if command -v shfmt &>/dev/null; then \
		echo "Formatting shell scripts..."; \
		shfmt -w -i 4 lib/*.sh bin/cc-*; \
		echo "✓ Formatted"; \
	else \
		echo "shfmt not found. Install: brew install shfmt"; \
	fi

# Lint shell scripts (if shellcheck is installed)
# NOTE: bin/cc-* pattern excludes .ts files; -S error ignores warnings/info/style
lint:
	@if command -v shellcheck &>/dev/null; then \
		echo "Linting shell scripts..."; \
		shellcheck -S error lib/*.sh bin/cc-*; \
		echo "✓ Lint passed"; \
	else \
		echo "shellcheck not found. Install: brew install shellcheck"; \
	fi

# Update golden test baselines
# Run after intentionally changing prompts in lib/prompt-builder.sh
update-golden:
	@echo "Updating golden test baselines..."
	@REFLECTION_BASE=$$(mktemp -d) && \
		source lib/prompt-builder.sh && \
		build_system_prompt enhance-interactive > tests/golden/enhance-interactive.golden && \
		build_system_prompt enhance-auto > tests/golden/enhance-auto.golden && \
		build_system_prompt expand-interactive /tmp/golden-test-output.md > tests/golden/expand-interactive.golden && \
		build_system_prompt expand-auto /tmp/golden-test-output.md > tests/golden/expand-auto.golden
	@echo "✓ Golden files updated. Review with: git diff tests/golden/"

# Show logs
logs:
	@tail -f ~/.claude/reflections/logs/cc-reflection.log

# Show current session ID
session-id:
	@bun lib/session-id.ts

# List current session's seeds
list-seeds:
	@bun lib/reflection-state.ts list | bun -e "const seeds = JSON.parse(await Bun.stdin.text()); seeds.forEach(s => console.log(\`[\$${s.freshness_tier}] \$${s.title}\`));"

# ============================================================================
# CI/CD
# ============================================================================

ci: test lint
	@echo "✓ CI checks passed"

# ============================================================================
# EVALS
# ============================================================================

# Score a single enhanced output
# Usage: make eval-score CASE=05-add-validation
eval-score:
	@if [ -z "$(CASE)" ]; then \
		echo "Usage: make eval-score CASE=<case-name>"; \
		echo "Example: make eval-score CASE=05-add-validation"; \
		exit 1; \
	fi
	@bun tests/evals/lib/scorer.ts \
		tests/evals/enhance/cases/$(CASE).txt \
		tests/evals/enhance/outputs/$(CASE).enhanced.md

# Score all enhanced outputs (detailed)
eval-score-all:
	@echo "Scoring all enhanced outputs..."
	@for f in tests/evals/enhance/outputs/*.enhanced.md; do \
		case=$$(basename "$$f" .enhanced.md); \
		echo "\n=== $$case ==="; \
		bun tests/evals/lib/scorer.ts \
			"tests/evals/enhance/cases/$$case.txt" \
			"$$f" 2>/dev/null || echo "  (no output yet)"; \
	done

# Summary with adversarial cases separated
eval-summary:
	@bun tests/evals/lib/summary.ts

# Run enhance agent on a single case
# Usage: make eval-run CASE=01-create-script
eval-run:
	@if [ -z "$(CASE)" ]; then \
		echo "Usage: make eval-run CASE=<case-name>"; \
		echo "Example: make eval-run CASE=01-create-script"; \
		echo ""; \
		echo "Or run all missing:"; \
		echo "  make eval-run-all"; \
		exit 1; \
	fi
	@./tests/evals/lib/run-enhance.sh $(CASE)

# Run enhance agent on all cases without outputs
eval-run-all:
	@./tests/evals/lib/run-enhance.sh --all

# List eval cases
eval-list:
	@echo "Eval cases:"
	@for f in tests/evals/enhance/cases/*.txt; do \
		name=$$(basename "$$f" .txt); \
		output="tests/evals/enhance/outputs/$$name.enhanced.md"; \
		if [ -f "$$output" ]; then \
			echo "  ✓ $$name"; \
		else \
			echo "  · $$name (no output)"; \
		fi; \
	done

# Run blind execution test on a single case
# Usage: make eval-blind CASE=01-create-script
eval-blind:
	@if [ -z "$(CASE)" ]; then \
		echo "Usage: make eval-blind CASE=<case-name>"; \
		echo "Example: make eval-blind CASE=01-create-script"; \
		exit 1; \
	fi
	@bun tests/evals/lib/blind-exec.ts \
		tests/evals/enhance/outputs/$(CASE).enhanced.md
