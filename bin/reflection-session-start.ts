#!/usr/bin/env bun

/**
 * SessionStart Hook - Register session UUID as environment variable
 *
 * CLAUDE_ENV_FILE is only available in SessionStart hooks.
 * Writing `export VAR=value` to it persists the variable for the entire session.
 * Every subsequent Bash command (and bun invocation) sees it.
 *
 * This makes CC_REFLECTION_SESSION_ID available to:
 * - reflection-utils.ts (reflection-specific operations)
 * - session-id.ts getClaudeSessionId()
 * - Any hook or skill that needs the current session UUID
 *
 * NOTE: CC_DICE_SESSION_ID is set by cc-dice's own SessionStart hook.
 */

try {
  const input: { session_id?: string } = await Bun.stdin.json();
  const envFile = process.env.CLAUDE_ENV_FILE;
  const sessionId = input.session_id;

  if (envFile && sessionId && /^[A-Za-z0-9-]{1,128}$/.test(sessionId)) {
    const { appendFileSync } = await import("fs");
    appendFileSync(envFile, `export CC_REFLECTION_SESSION_ID="${sessionId}"\n`);
  }
} catch {
  // Fail silently — don't block session start
}
