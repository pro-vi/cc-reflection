#!/usr/bin/env bash
# Command handler for cc-hall reflection module
# Args: $1 = raw command, $2 = prompt file path

set -e

# Resolve to cc-reflection root (dir may be symlinked)
_HANDLER_PATH="${BASH_SOURCE[0]}"
_HANDLER_DIR="$(cd "$(dirname "$_HANDLER_PATH")" && pwd -P)"
REFLECTION_ROOT="$(cd "$_HANDLER_DIR/.." && pwd -P)"

source "$REFLECTION_ROOT/lib/cc-common.sh"
source "$REFLECTION_ROOT/lib/prompt-builder.sh"
source "${HALL_LIB_DIR}/hall-common.sh"

CMD="$1"
FILE="$2"

REFLECTION_BIN="$REFLECTION_ROOT/bin"

# ── Guide and noop entries ─────────────────────────────────────────
case "$CMD" in
    rf-noop|rf-info\ *)
        exit $HALL_RC_RELOAD ;;
esac

# ── Seed expansion ────────────────────────────────────────────────
if [[ "$CMD" == cc-reflect-expand\ * ]]; then
    MODE=$(echo "$CMD" | cut -d' ' -f2)
    SEED_ID=$(echo "$CMD" | cut -d' ' -f3)
    cc_log_info "Hall: expanding seed $SEED_ID (mode: $MODE)"
    "$REFLECTION_BIN/cc-reflect-expand" "$MODE" "$SEED_ID" "$FILE"
    exit $HALL_RC_CLOSE
fi

# ── Toggle commands (all return reload) ───────────────────────────
case "$CMD" in
    cc-reflect-toggle-mode)
        "$REFLECTION_BIN/cc-reflect-toggle-mode" > /dev/null
        exit $HALL_RC_RELOAD
        ;;
    cc-reflect-toggle-model)
        "$REFLECTION_BIN/cc-reflect-toggle-haiku" > /dev/null
        exit $HALL_RC_RELOAD
        ;;
    cc-reflect-toggle-filter)
        "$REFLECTION_BIN/cc-reflect-toggle-filter" > /dev/null
        exit $HALL_RC_RELOAD
        ;;
    cc-reflect-toggle-context)
        "$REFLECTION_BIN/cc-reflect-toggle-context" > /dev/null
        exit $HALL_RC_RELOAD
        ;;
    cc-reflect-toggle-permissions)
        "$REFLECTION_BIN/cc-reflect-toggle-permissions" > /dev/null
        exit $HALL_RC_RELOAD
        ;;
    cc-reflect-archive-outdated)
        RESULT=$(bun "$REFLECTION_ROOT/lib/reflection-state.ts" archive-outdated 2>/dev/null)
        ARCHIVED=$(echo "$RESULT" | bun -e "console.log(JSON.parse(await Bun.stdin.text()).archived)" 2>/dev/null)
        if [ "$ARCHIVED" = "0" ]; then
            echo "No outdated seeds to archive." >&2
        else
            echo "Archived $ARCHIVED outdated seed(s)" >&2
        fi
        exit $HALL_RC_RELOAD
        ;;
    cc-reflect-archive-all)
        RESULT=$(bun "$REFLECTION_ROOT/lib/reflection-state.ts" archive-all 2>/dev/null)
        ARCHIVED=$(echo "$RESULT" | bun -e "console.log(JSON.parse(await Bun.stdin.text()).archived)" 2>/dev/null)
        if [ "$ARCHIVED" = "0" ]; then
            echo "No active seeds to archive." >&2
        else
            echo "Archived $ARCHIVED seed(s)" >&2
        fi
        exit $HALL_RC_RELOAD
        ;;
    cc-reflect-purge-archived)
        RESULT=$(bun "$REFLECTION_ROOT/lib/reflection-state.ts" delete-archived 2>/dev/null)
        DELETED=$(echo "$RESULT" | bun -e "console.log(JSON.parse(await Bun.stdin.text()).deleted)" 2>/dev/null)
        if [ "$DELETED" = "0" ]; then
            echo "No archived seeds to purge." >&2
        else
            echo "Purged $DELETED archived seed(s)" >&2
        fi
        exit $HALL_RC_RELOAD
        ;;
esac

# Not handled — let hall fall through
exit $HALL_RC_NOT_HANDLED
