#!/usr/bin/env bash
# Preview handler for cc-hall reflection module
# Receives: $1=clean command, $2=label (routing tag stripped by cc-hall)

set -e

# Resolve to cc-reflection root (dir may be symlinked)
_PREVIEW_PATH="${BASH_SOURCE[0]}"
_PREVIEW_DIR="$(cd "$(dirname "$_PREVIEW_PATH")" && pwd -P)"
REFLECTION_ROOT="$(cd "$_PREVIEW_DIR/.." && pwd -P)"

source "$REFLECTION_ROOT/lib/cc-common.sh"

RAW_CMD="$1"
[ -z "$RAW_CMD" ] && exit 0

# ── Seed preview ──────────────────────────────────────────────────
if [[ "$RAW_CMD" =~ ^cc-reflect-expand ]]; then
    SEED_ID=$(echo "$RAW_CMD" | awk '{print $3}')
    [ -z "$SEED_ID" ] && exit 0

    SEED_JSON=$(cc_bun_run "$REFLECTION_ROOT/lib/reflection-state.ts" get "$SEED_ID" 2>/dev/null)
    [ -z "$SEED_JSON" ] || [ "$SEED_JSON" = "null" ] && { echo "Seed not found: $SEED_ID"; exit 0; }

    TITLE=$(echo "$SEED_JSON" | bun -e "const s = JSON.parse(await Bun.stdin.text()); console.log(s.title);" 2>/dev/null)
    RATIONALE=$(echo "$SEED_JSON" | bun -e "const s = JSON.parse(await Bun.stdin.text()); console.log(s.rationale);" 2>/dev/null)
    CREATED_AT=$(echo "$SEED_JSON" | bun -e "const s = JSON.parse(await Bun.stdin.text()); const d = new Date(s.created_at); console.log(d.toLocaleString());" 2>/dev/null)
    EXPANSION_COUNT=$(echo "$SEED_JSON" | bun -e "const s = JSON.parse(await Bun.stdin.text()); console.log(s.expansions?.length || 0);" 2>/dev/null)

    cat <<EOF
  REFLECTION SEED

  $TITLE

  Rationale:
  $RATIONALE

  Created: $CREATED_AT
  ID: $SEED_ID
EOF

    if [ "$EXPANSION_COUNT" -gt 0 ] 2>/dev/null; then
        echo ""
        echo "  Expanded $EXPANSION_COUNT time(s)"
        echo "$SEED_JSON" | bun -e "
            const s = JSON.parse(await Bun.stdin.text());
            for (let i = 0; i < s.expansions.length; i++) {
                const e = s.expansions[i];
                const d = new Date(e.timestamp).toLocaleString();
                console.log('  [' + (i+1) + '] ' + d);
                if (e.conclusion) console.log('      ' + e.conclusion);
            }
        " 2>/dev/null
    fi
    exit 0
fi

# ── Toggle previews ───────────────────────────────────────────────
case "$RAW_CMD" in
    cc-reflect-toggle-mode)
        cat <<'EOF'
  EXPANSION MODE

  Interactive: Opens tmux window for conversation
  with the thought-agent. Ask follow-ups.

  Auto: Runs non-interactively. Expansion completes
  automatically and returns the result.
EOF
        ;;
    cc-reflect-toggle-model)
        cat <<'EOF'
  MODEL SELECTION

  Opus:   Most capable. Deep reasoning.
  Sonnet: Fast and capable. Good balance.
  Haiku:  Fastest. Quick iterations.

  Cycles: Opus -> Sonnet -> Haiku -> Opus
EOF
        ;;
    cc-reflect-toggle-filter)
        cat <<'EOF'
  MENU FILTER

  Active:   Fresh seeds only
  Outdated: Stale seeds (> 3 days)
  Archived: Manually archived seeds
  All:      Everything
EOF
        ;;
    cc-reflect-toggle-context)
        cat <<'EOF'
  CONTEXT TURNS

  How many recent conversation turns to include
  when expanding a seed.

  0:  No context (seed only)
  3:  Brief context
  5:  Moderate context
  10: Full context
EOF
        ;;
    cc-reflect-toggle-permissions)
        cat <<'EOF'
  PERMISSIONS

  Off: Agent asks before dangerous operations.
  On:  Runs with --dangerously-skip-permissions.
       Faster but less safe.

  Only enable if you trust the codebase context.
EOF
        ;;
    cc-reflect-archive-outdated)
        cat <<'EOF'
  ARCHIVE OUTDATED

  Archives only stale seeds (> 3 days old).
  Fresh seeds are kept. No permanent deletion.
  Use regularly to keep seed list manageable.
EOF
        ;;
esac
