#!/usr/bin/env bun

/**
 * Centralized identity calculation for storage + isolation
 *
 * WHY: The identifier used by bash (cc-common.sh) and TypeScript must match,
 *      otherwise seeds/state written by one side become invisible to the other.
 * ASSUMPTION: process.cwd() and bash `pwd` return identical paths
 * TESTED BY: tests/test_session_id.bats::bash and TypeScript produce identical session IDs
 *
 * This module is the TypeScript source of truth for the "effective session id"
 * used to namespace reflection state on disk.
 * Any changes must be made here AND in lib/cc-common.sh.
 *
 * There are two scopes, resolved by priority:
 * - Conversation identity: Claude Code session UUID (per-conversation isolation)
 * - Project identity: 12-char MD5 hash of the working directory (fallback)
 *
 * Actual behavior:
 * - If a Claude UUID is available, seeds/state are per-conversation.
 * - Otherwise (standalone / legacy), seeds/state are per-project.
 */

import { createHash } from 'crypto';
import { existsSync, readFileSync } from 'fs';
import { join } from 'path';

/**
 * Get the project hash for the current directory
 * This is the project identity used when no Claude UUID is available.
 * It's also used to locate the legacy "current session" file on disk.
 *
 * CRITICAL: Use PWD env var (logical path) instead of process.cwd() (physical path)
 * WHY: On macOS, /tmp is symlink to /private/tmp
 *      bash `pwd` returns /tmp (logical), process.cwd() returns /private/tmp (physical)
 *      This caused hash mismatch in tests
 * TESTED BY: tests/integration/test_bash_ts_session_id.bats
 */
export function getProjectHash(): string {
  const cwd = process.env.PWD || process.cwd();
  return createHash('md5').update(cwd).digest('hex').substring(0, 12);
}

export function getReflectionsBaseDir(): string | null {
  if (process.env.REFLECTION_BASE) return process.env.REFLECTION_BASE;
  if (!process.env.HOME) return null;
  return join(process.env.HOME, '.claude', 'reflections');
}

export function getReflectionsBaseDirOrThrow(): string {
  const baseDir = getReflectionsBaseDir();
  if (!baseDir) {
    throw new Error('Cannot resolve reflections base dir: set REFLECTION_BASE or HOME');
  }
  return baseDir;
}

/**
 * Get Claude Code session UUID if available
 * WHY: Enables per-conversation session isolation when a hook records the current session
 * SYNC: Must match cc_get_claude_session_id in lib/cc-common.sh
 *
 * Resolution order:
 * 1. CC_DICE_SESSION_ID env var (set by cc-dice SessionStart hook)
 * 2. CC_REFLECTION_SESSION_ID env var (set by cc-reflection SessionStart hook)
 * 3. File-based lookup (legacy, kept for backward compat)
 */
export function getClaudeSessionId(): string | null {
  // Primary: env var set by cc-dice's SessionStart hook
  if (process.env.CC_DICE_SESSION_ID) {
    return process.env.CC_DICE_SESSION_ID;
  }
  // Backward compat: old cc-reflection SessionStart hook
  if (process.env.CC_REFLECTION_SESSION_ID) {
    return process.env.CC_REFLECTION_SESSION_ID;
  }

  // Fallback: file-based (legacy, kept for backward compat)
  const baseDir = getReflectionsBaseDir();
  if (!baseDir) return null;

  const projectHash = getProjectHash();
  const sessionFile = join(baseDir, 'sessions', projectHash, 'current');

  try {
    if (!existsSync(sessionFile)) return null;
    const sessionId = readFileSync(sessionFile, 'utf8').trim();
    return sessionId.length > 0 ? sessionId : null;
  } catch {
    return null;
  }
}

/**
 * Get session ID for current context
 *
 * Priority:
 * 1. CLAUDE_SESSION_ID environment variable (explicit override for testing)
 * 2. Claude Code session UUID (from hook, if present)
 * 3. Project hash (12-char MD5 of directory)
 *
 * @returns Session ID string
 */
export function getSessionId(): string {
  // Allow explicit override for testing
  if (process.env.CLAUDE_SESSION_ID) {
    return process.env.CLAUDE_SESSION_ID;
  }

  const claudeSessionId = getClaudeSessionId();
  if (claudeSessionId) return claudeSessionId;

  return getProjectHash();
}

// CLI interface for testing and debugging
// Usage: bun lib/session-id.ts
if (import.meta.main) {
  const sessionId = getSessionId();
  console.log(sessionId);

  // For debugging: show which method was used
  if (process.env.DEBUG) {
    const projectHash = getProjectHash();
    const claudeSessionId = getClaudeSessionId();

    if (process.env.CLAUDE_SESSION_ID) {
      console.error(`[DEBUG] Source: CLAUDE_SESSION_ID env var (test override)`);
    } else if (process.env.CC_DICE_SESSION_ID) {
      console.error(`[DEBUG] Source: CC_DICE_SESSION_ID env var (cc-dice SessionStart hook)`);
    } else if (process.env.CC_REFLECTION_SESSION_ID) {
      console.error(`[DEBUG] Source: CC_REFLECTION_SESSION_ID env var (cc-reflection SessionStart hook)`);
    } else if (claudeSessionId) {
      console.error(`[DEBUG] Source: Claude session UUID file (legacy)`);
    } else {
      console.error(`[DEBUG] Source: Project hash`);
    }

    console.error(`[DEBUG] Project hash: ${projectHash}`);
    console.error(`[DEBUG] Claude session: ${claudeSessionId || '<none>'}`);
    console.error(`[DEBUG] CC_DICE_SESSION_ID: ${process.env.CC_DICE_SESSION_ID || '<not set>'}`);
    console.error(`[DEBUG] CC_REFLECTION_SESSION_ID: ${process.env.CC_REFLECTION_SESSION_ID || '<not set>'}`);
    console.error(`[DEBUG] PWD: ${process.env.PWD || process.cwd()}`);
  }
}
