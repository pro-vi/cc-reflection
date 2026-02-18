#!/usr/bin/env bun

/**
 * Reflection Utilities — CLI dispatcher
 *
 * Thin entrypoint for reflection-specific operations.
 * Dice mechanics, transcript path resolution, and cooldown markers
 * have moved to cc-dice.
 *
 * Remaining: get-recent (extract recent turns for expand prompt context)
 */

import { getRecentTurns } from "./transcript";

// Re-export for backward compatibility (expand prompt uses this)
export { getRecentTurns } from "./transcript";

// CLI interface
if (import.meta.main) {
  const args = process.argv.slice(2);
  const command = args[0];

  switch (command) {
    case "get-recent": {
      const n = parseInt(args[1], 10);
      if (isNaN(n) || n <= 0) {
        console.error("Usage: reflection-utils.ts get-recent <n> <transcript-path>");
        process.exit(1);
      }
      const transcriptPath = args[2];
      if (!transcriptPath) {
        console.error("Usage: reflection-utils.ts get-recent <n> <transcript-path>");
        console.error("Transcript path is required. Use cc-dice for path resolution.");
        process.exit(1);
      }
      const turns = await getRecentTurns(transcriptPath, n);
      if (turns.length === 0) {
        console.error("No turns found");
        process.exit(1);
      }
      // Output as newline-separated for easy parsing
      console.log(turns.join("\n\n---\n\n"));
      break;
    }
    default:
      console.log(`Commands:
  get-recent <n> <transcript-path>   Get last N conversation turns

Dice, transcript path resolution, and cooldown markers have moved to cc-dice.
See: https://github.com/pro-vi/cc-dice`);
  }
}
