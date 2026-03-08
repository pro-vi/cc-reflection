#!/usr/bin/env bash
# Preview handler for cc-hall reflection module
# Receives: $1=clean command, $2=label (routing tag stripped by cc-hall)

set -e

# Resolve to cc-reflection root (dir may be symlinked)
_PREVIEW_PATH="${BASH_SOURCE[0]}"
_PREVIEW_DIR="$(cd "$(dirname "$_PREVIEW_PATH")" && pwd -P)"
REFLECTION_ROOT="$(cd "$_PREVIEW_DIR/.." && pwd -P)"

HALL_LIB_DIR="${HALL_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../cc-hall/lib" && pwd)}"
source "$HALL_LIB_DIR/hall-common.sh"
source "$HALL_LIB_DIR/hall-render.sh"
source "$REFLECTION_ROOT/lib/cc-common.sh"

RAW_CMD="$1"
[ -z "$RAW_CMD" ] && exit 0

# ── Guide ────────────────────────────────────────────────────────

case "$RAW_CMD" in
    rf-info\ guide)
        cat <<'EOF' | hall_render_markdown
**Reflection — Self-Reflection Seeds**

Claude creates **reflection seeds** during work:
observations about architecture, decisions, or
process patterns worth examining.

**Workflow**

| Step | Action |
|------|--------|
| 1 | Agent creates seed via `/reflection` skill |
| 2 | Press `Ctrl+G`, open Reflection tab |
| 3 | Select seed → thought agent investigates |
| 4 | Result lands in your input box |

**Keybindings**

| Key | Action |
|-----|--------|
| `Enter` | Expand seed / toggle setting |
| `Ctrl+D` | Delete seed (permanent) |
| `Ctrl+A` | Archive / unarchive seed |
| `Ctrl+F` | Cycle filter |
| `Ctrl+/` | Toggle preview pane |
EOF
        exit 0 ;;

    rf-noop)
        exit 0 ;;
esac

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

    {
        printf '**%s**\n\n' "$TITLE"
        printf '%s\n\n' "$RATIONALE"
        printf '`%s` · %s\n' "$SEED_ID" "$CREATED_AT"
    } | hall_render_markdown

    if [ "$EXPANSION_COUNT" -gt 0 ] 2>/dev/null; then
        printf '\n  \033[2mExpanded %s time(s)\033[0m\n' "$EXPANSION_COUNT"
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

    printf '\n  Press Enter to expand.\n'
    exit 0
fi

# ── Toggle previews ───────────────────────────────────────────────
case "$RAW_CMD" in
    cc-reflect-toggle-mode)
        cat <<'EOF' | hall_render_markdown
**Expansion Mode**

| Mode | Description |
|------|-------------|
| **Interactive** | Opens tmux window for conversation with the thought agent. Ask follow-ups. |
| **Auto** | Runs non-interactively. Expansion completes automatically. |
EOF
        printf '\n  Press Enter to toggle.\n'
        ;;
    cc-reflect-toggle-model)
        cat <<'EOF' | hall_render_markdown
**Model**

| Model | Description |
|-------|-------------|
| **Opus** | Most capable. Deep reasoning. |
| **Sonnet** | Fast and capable. Good balance. |
| **Haiku** | Fastest. Quick iterations. |
EOF
        printf '\n  Press Enter to cycle.\n'
        ;;
    cc-reflect-toggle-filter)
        cat <<'EOF' | hall_render_markdown
**Seed Filter**

| Filter | Shows |
|--------|-------|
| **Active** | Fresh 🌱 and growing 💭 seeds |
| **Outdated** | Stale 💤 seeds (> 3 days) |
| **Archived** | Manually archived 📦 seeds |
| **All** | Everything |
EOF
        printf '\n  Press Enter to cycle. `Ctrl+F` also cycles.\n'
        ;;
    cc-reflect-toggle-context)
        cat <<'EOF' | hall_render_markdown
**Context Turns**

How many recent conversation turns to include
when expanding a seed.

| Value | Description |
|-------|-------------|
| **Off** | Seed only, no conversation context |
| **3** | Brief context |
| **5** | Moderate context |
| **10** | Full context |
EOF
        printf '\n  Press Enter to cycle.\n'
        ;;
    cc-reflect-toggle-permissions)
        cat <<'EOF' | hall_render_markdown
**Skip Permissions**

| State | Description |
|-------|-------------|
| **Off** | Agent asks before dangerous operations |
| **On** | Runs with `--skip-permissions`. Faster but less safe. |

Only enable if you trust the codebase context.
EOF
        printf '\n  Press Enter to toggle.\n'
        ;;
    cc-reflect-archive-outdated)
        cat <<'EOF' | hall_render_markdown
**Archive Outdated**

Archives only stale seeds (> 3 days old).
Fresh seeds are kept. No permanent deletion.

Use regularly to keep the seed list manageable.
EOF
        printf '\n  Press Enter to archive.\n'
        ;;
    cc-reflect-archive-all)
        cat <<'EOF' | hall_render_markdown
**Archive All**

Archives every active seed in the current project.
Seeds are not deleted — they move to the archived filter.

Use when starting a new phase of work.
EOF
        printf '\n  Press Enter to archive all.\n'
        ;;
    cc-reflect-purge-archived)
        cat <<'EOF' | hall_render_markdown
**Purge Archived**

Permanently deletes all archived seeds.
This cannot be undone.

Active and outdated seeds are not affected.
EOF
        printf '\n  \033[33m⚠ Destructive action\033[0m\n'
        printf '  Press Enter to purge.\n'
        ;;
esac

exit 0
