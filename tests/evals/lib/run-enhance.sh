#!/usr/bin/env bash
# Run enhance agent on a single eval case
#
# Usage: ./run-enhance.sh <case-name>
# Example: ./run-enhance.sh 01-create-script
#
# Runs Claude with enhance-auto system prompt and saves output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CASES_DIR="$PROJECT_ROOT/tests/evals/enhance/cases"
OUTPUTS_DIR="$PROJECT_ROOT/tests/evals/enhance/outputs"
GOLDEN_DIR="$PROJECT_ROOT/tests/golden"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <case-name> [--all]"
    echo ""
    echo "Examples:"
    echo "  $0 01-create-script    # Run single case"
    echo "  $0 --all               # Run all cases without outputs"
    exit 1
fi

run_case() {
    local case_name="$1"
    local input_file="$CASES_DIR/${case_name}.txt"
    local output_file="$OUTPUTS_DIR/${case_name}.enhanced.md"

    if [ ! -f "$input_file" ]; then
        echo "Error: Case file not found: $input_file"
        return 1
    fi

    echo "=== Running: $case_name ==="
    echo "Input: $(cat "$input_file")"

    # Create temp file with input
    local temp_file
    temp_file=$(mktemp)
    cp "$input_file" "$temp_file"

    # Run enhance agent
    cd "$PROJECT_ROOT"
    FILE="$temp_file" claude \
        --model haiku \
        --dangerously-skip-permissions \
        --print \
        -p "Enhance the prompt in the FILE environment variable." \
        --append-system-prompt "$(cat "$GOLDEN_DIR/enhance-auto.golden")" \
        > /dev/null 2>&1

    # Copy result
    cp "$temp_file" "$output_file"
    rm -f "$temp_file"

    echo "Output saved: $output_file"
    echo ""
}

if [ "$1" = "--all" ]; then
    for case_file in "$CASES_DIR"/*.txt; do
        case_name=$(basename "$case_file" .txt)
        output_file="$OUTPUTS_DIR/${case_name}.enhanced.md"

        if [ -f "$output_file" ]; then
            echo "Skipping $case_name (output exists)"
        else
            run_case "$case_name"
        fi
    done

    echo "Done. Run 'make eval-score-all' to see scores."
else
    run_case "$1"
fi
