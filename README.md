# cc-reflection

Self-reflection for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Claude creates **reflection seeds** during work: observations about architecture, product decisions, or process patterns worth examining. Seeds are cheap to capture and don't interrupt flow. Later, you press **Ctrl+G** to expand a seed. A thought agent investigates the concern, reads relevant code, and writes a plan for the proposed artifact. The result lands directly in your input box. Press Enter.

The agent reflects. But when *you* engage, that's when the system comes alive.

## Install

Requires [bun](https://bun.sh), [git](https://git-scm.com), [fzf](https://github.com/junegunn/fzf), [tmux](https://github.com/tmux/tmux), and [jq](https://jqlang.github.io/jq/).

```bash
curl -fsSL https://raw.githubusercontent.com/pro-vi/cc-reflection/main/install.sh | bash
```

Or clone locally:

```bash
git clone https://github.com/pro-vi/cc-reflection.git
cd cc-reflection && ./install.sh
```

Recommended: install [cc-dice](https://github.com/pro-vi/cc-dice) for agent-side proactive reflection (see [How it works](#how-it-works)).

```bash
cc-reflect --check     # verify installation
./install.sh uninstall # remove
```

## How it works

**Two entry points:**

1. **Agent-side** (`/reflection` skill + [cc-dice](https://github.com/pro-vi/cc-dice)): The `/reflection` skill is available in every session, but agents rarely reflect unprompted. [cc-dice](https://github.com/pro-vi/cc-dice) solves this. It accumulates dice across turns and eventually prompts the agent to check if anything is worth reflecting on. The longer the session, the higher the pressure. Without cc-dice the agent can still reflect, but loses proactive triggering.

2. **Your side** (Ctrl+G): `cc-reflect` is your EDITOR. Press Ctrl+G in Claude Code to open the fzf menu: browse seeds, expand them, or edit your prompt. Expanding a seed spawns a thought agent that reads relevant code and writes a plan for the artifact the seed proposed. In interactive mode you can steer the expansion. The result lands in your input box as a ready-to-send prompt for your main agent.

Seeds persist across conversations in the same project. Start a new session tomorrow and your seeds are still there.

**Three examinations** (吾日三省吾身):

- **一省**: "Am I building this correctly?" (engineering)
- **二省**: "Am I building the right thing?" (product)
- **三省**: "How am I working?" (process)

**What makes a seed:** Not every observation becomes a seed. The skill runs an internal discernment process: generate candidate seedlings, discard the weak ones, present only survivors. Each seed must propose a concrete artifact ("update SKILL.md with X", "create eslint rule for Y"). If you can't name the artifact, the observation isn't ripe. Tactical fixes ("this field needs validation") stay as todos. Seeds capture strategic patterns ("user pointed out missing validation twice, worth encoding"). Nothing surviving discernment is 今日無省: clarity, not failure.

## Ctrl+G

When you press Ctrl+G, `cc-reflect` opens an fzf menu inside tmux. What you can do:

**Edit prompt**: Open your current prompt in your editor (vi, VS Code, Cursor, Zed, Windsurf, Antigravity). Save and close to send it back to Claude.

**Enhance prompt**: A separate agent rewrites your draft for clarity and adds acceptance criteria. Runs in interactive or auto mode depending on your settings.

**Expand seeds**: Seeds appear with freshness indicators (🌱 fresh, 💭 growing, 💤 stale, 📦 archived). Toggle the preview pane with `Ctrl+/` to see rationale. Select a seed to spawn a thought agent that investigates the concern and produces an actionable prompt: a plan for the artifact the seed proposed. The thought agent has hardened system prompts with mandatory verification gates: it must check every file path it references actually exists, won't speculate about code it hasn't read, and records a conclusion that gets attached to the seed for future reference. In interactive mode you can steer the direction before it finalizes. When done, `Ctrl+C` to end the thought agent, then `Ctrl+D` to detach from tmux. The result goes straight into your input box, ready to send.

**Settings** (all persistent):

| Setting | Toggle | Options |
|---------|--------|---------|
| Expansion mode | `🔄 Mode` | interactive / auto |
| Model | `🤖 Model` | opus / sonnet / haiku |
| Filter | `🔍 Filter` | active / outdated / archived / all |
| Context turns | `💬 Context` | 0 / 3 / 5 / 10 |
| Permissions | `🔐 Permissions` | skip / require |

**Keybindings:**

| Key | Action |
|-----|--------|
| `Ctrl+D` | Delete seed (permanent) |
| `Ctrl+A` | Archive / unarchive seed |
| `Ctrl+F` | Cycle filter |
| `Ctrl+/` | Toggle preview pane |
| `ESC` | Cancel and exit |

## Configuration

`~/.claude/reflections/config.json`:

```json
{
  "enabled": true,
  "ttl_hours": 72,
  "expansion_mode": "interactive",
  "model": "opus",
  "menu_filter": "active",
  "context_turns": 3,
  "skip_permissions": false
}
```

Seeds are never auto-deleted. They go stale after `ttl_hours` and can be archived. A SessionStart hook registers `CC_REFLECTION_SESSION_ID` so seeds are scoped to your project directory, not a single conversation.

## Architecture

| Component | Location | Role |
|-----------|----------|------|
| Skill | `.claude/skills/reflection/SKILL.md` | Teaches Claude when/how to create seeds |
| State manager | `lib/reflection-state.ts` | Seed lifecycle: write, read, expire, dedupe |
| EDITOR binary | `bin/cc-reflect` | Ctrl+G opens fzf menu via Claude Code's EDITOR hook |
| Thought agent | `bin/cc-reflect-expand` | Spawns Claude instance to expand seeds |
| SessionStart hook | `bin/reflection-session-start.ts` | Registers session UUID for cross-conversation persistence |
| Dice | [cc-dice](https://github.com/pro-vi/cc-dice) (recommended) | Accumulating pressure model that prompts agent to reflect |

All state in `~/.claude/reflections/` as flat JSON.

<details>
<summary>CLI reference</summary>

```bash
# Seeds
bun lib/reflection-state.ts list [active|outdated|archived|all]
bun lib/reflection-state.ts list-all
bun lib/reflection-state.ts get <seed-id>
bun lib/reflection-state.ts write "<title>" "<rationale>" "<file>" "<start>" "<end>"
bun lib/reflection-state.ts delete <seed-id>
bun lib/reflection-state.ts archive <seed-id>
bun lib/reflection-state.ts unarchive <seed-id>
bun lib/reflection-state.ts archive-all
bun lib/reflection-state.ts archive-outdated
bun lib/reflection-state.ts delete-archived
bun lib/reflection-state.ts cleanup
bun lib/reflection-state.ts conclude <seed-id> "<summary>" [result-path]
```

</details>

<details>
<summary>Settings CLI</summary>

```bash
# Filter
bun lib/reflection-state.ts get-filter
bun lib/reflection-state.ts set-filter <active|outdated|archived|all>
bun lib/reflection-state.ts cycle-filter

# Model
bun lib/reflection-state.ts get-model
bun lib/reflection-state.ts set-model <opus|sonnet|haiku>
bun lib/reflection-state.ts cycle-model

# Context turns
bun lib/reflection-state.ts get-context-turns
bun lib/reflection-state.ts set-context-turns <0-20>
bun lib/reflection-state.ts cycle-context-turns

# Permissions
bun lib/reflection-state.ts get-permissions
bun lib/reflection-state.ts set-permissions <enabled|disabled>
```

</details>

<details>
<summary>Security</summary>

- Seed titles reject shell metacharacters; IDs validated with strict regex
- Only allowlisted commands executable from menu
- JSON validated on load; malformed seeds skipped
- Single-user, local-only deployment assumed
- See [`SECURITY.md`](./SECURITY.md) and `tests/security/test_shell_injection.bats`

</details>

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## License

MIT
