# Improve Error Handling in the Hooks

## Context

The cc-reflection project has two main Claude Code hooks:

1. **SessionStart hook** (`bin/reflection-session-start.ts` - 61 lines)
   - Captures Claude Code session UUID and writes to `~/.claude/reflections/sessions/<projectHash>/current`
   - Stores session metadata for transcript reading

2. **Skill Activation hook** (`internal_docs/archived-hooks/skill-activation-reflection.ts`)
   - UserPromptSubmit hook that suggests reflection based on session depth
   - Uses depth-scaled dice rolling (5-15% chance depending on conversation depth)
   - One-per-session cooldown after triggering

Both hooks are deployed to `~/.claude/hooks/` via `install.sh` and registered in Claude Code's `settings.json`.

## Current Error Handling Issues

1. **Silent Failures in SessionStart Hook**
   - Line 54-56: Catches all errors but exits with 0 (success) regardless
   - Hides file permission issues, directory creation failures, or JSON parse errors
   - User can't tell if hook is actually working
   - Non-fatal error strategy may be wrong - some errors should block/signal failure

2. **No Input Validation**
   - SessionStart hook accepts any JSON without validating required fields (`session_id`, `working_directory`)
   - Could fail unpredictably if Claude Code passes malformed input

3. **Incomplete Error Context**
   - Error messages are generic (just `(error as Error).message`)
   - No context about what operation failed or why
   - Makes debugging difficult for users

4. **No Logging to Centralized System**
   - Current implementation logs to `console.error` only
   - Should use the project's centralized logging at `~/.claude/reflections/logs/cc-reflection.log`
   - Makes it invisible to diagnostic tools like `make logs`

5. **Race Conditions Not Handled**
   - Multiple concurrent sessions could race on writing `current` file
   - No atomic write or lock mechanism

6. **Missing Bun Runtime Errors**
   - `Bun.stdin.json()` could fail if input is not valid JSON or stream is closed
   - Not explicitly caught or handled

## Task

Improve error handling in hooks to be explicit, diagnostic, and integrated with the project's logging system:

**SessionStart hook** (`bin/reflection-session-start.ts`):
- Validate input before processing (check required fields)
- Distinguish between fatal errors (exit 2) and non-fatal ones (exit 0)
- Use centralized logging function (integrate with `cc-reflection.log`)
- Add atomic write for race condition safety (temporary file + rename)
- Provide detailed error messages with context (what operation, why it failed)

**Skill Activation hook** (when created/updated):
- Apply same error handling patterns
- Validate transcript path and input
- Proper error exit codes for Claude visibility

## Acceptance Criteria

**Done when:**
1. All input is validated before use with clear error messages
2. Errors provide enough context to diagnose (operation name, expected values, actual values)
3. Hook failures are logged to centralized `~/.claude/reflections/logs/cc-reflection.log`
4. Exit codes distinguish between fatal (2) and non-fatal (0) errors appropriately
5. Race condition on `current` file write is prevented with atomic operations
6. No breaking changes to existing hook behavior or Claude Code integration

## Out of Scope

- Changing hook triggering logic (dice rolls, cooldowns, depth thresholds)
- Modifying hook registration in `settings.json`
- User-facing UI/messaging changes
- Performance optimizations
