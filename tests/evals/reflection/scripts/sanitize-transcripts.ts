#!/usr/bin/env bun
/**
 * Sanitize golden transcripts to remove private information
 *
 * Actions:
 * 1. Replace /Users/provi paths with /home/user
 * 2. Strip metadata (cwd, sessionId, timestamps) - keep only message content
 */

const GOLDEN_DIR = `${import.meta.dir}/../golden`;

interface ContentBlock {
  type: string;
  text?: string;
  tool_use_id?: string;
  content?: string;
  name?: string;
  input?: unknown;
  id?: string;
}

interface TranscriptMessage {
  type: string;
  message?: {
    role?: string;
    content?: string | ContentBlock[];
  };
  // Metadata to strip
  cwd?: string;
  sessionId?: string;
  timestamp?: string;
  uuid?: string;
  parentUuid?: string;
  isSidechain?: boolean;
  userType?: string;
  toolUseResult?: unknown;
}

function sanitizePath(text: string): string {
  // Replace /Users/provi with /home/user
  return text.replace(/\/Users\/provi/g, "/home/user");
}

function sanitizeMessage(msg: TranscriptMessage): TranscriptMessage {
  // Keep only essential fields
  const sanitized: TranscriptMessage = {
    type: msg.type,
  };

  if (msg.message) {
    sanitized.message = {
      role: msg.message.role,
    };

    // Sanitize content
    if (typeof msg.message.content === "string") {
      sanitized.message.content = sanitizePath(msg.message.content);
    } else if (Array.isArray(msg.message.content)) {
      sanitized.message.content = msg.message.content.map((block) => {
        const sanitizedBlock: ContentBlock = { type: block.type };
        if (block.text !== undefined) {
          sanitizedBlock.text = sanitizePath(block.text);
        }
        if (block.tool_use_id !== undefined) {
          sanitizedBlock.tool_use_id = block.tool_use_id;
        }
        if (block.content !== undefined) {
          sanitizedBlock.content = sanitizePath(block.content);
        }
        if (block.name !== undefined) {
          sanitizedBlock.name = block.name;
        }
        if (block.input !== undefined) {
          // Sanitize input if it's an object with string values
          if (typeof block.input === "object" && block.input !== null) {
            sanitizedBlock.input = JSON.parse(sanitizePath(JSON.stringify(block.input)));
          } else {
            sanitizedBlock.input = block.input;
          }
        }
        if (block.id !== undefined) {
          sanitizedBlock.id = block.id;
        }
        return sanitizedBlock;
      });
    }
  }

  return sanitized;
}

async function processTranscript(filePath: string): Promise<{ before: number; after: number; pathsReplaced: number }> {
  const file = Bun.file(filePath);
  const content = await file.text();
  const lines = content.trim().split("\n");

  let pathsReplaced = 0;
  const sanitizedLines: string[] = [];

  for (const line of lines) {
    if (!line.trim()) continue;

    try {
      const msg = JSON.parse(line) as TranscriptMessage;
      const sanitized = sanitizeMessage(msg);
      const sanitizedJson = JSON.stringify(sanitized);

      // Count path replacements
      const beforePaths = (line.match(/\/Users\/provi/g) || []).length;
      pathsReplaced += beforePaths;

      sanitizedLines.push(sanitizedJson);
    } catch {
      // Keep malformed lines as-is but sanitize paths
      sanitizedLines.push(sanitizePath(line));
    }
  }

  const newContent = sanitizedLines.join("\n") + "\n";
  await Bun.write(filePath, newContent);

  return {
    before: content.length,
    after: newContent.length,
    pathsReplaced,
  };
}

async function main() {
  console.log("Sanitizing golden transcripts...\n");

  const goldens = await Array.fromAsync(new Bun.Glob("*").scan({ cwd: GOLDEN_DIR, onlyFiles: false }));
  let totalPathsReplaced = 0;
  let totalBytesSaved = 0;

  for (const golden of goldens.sort()) {
    const transcriptPath = `${GOLDEN_DIR}/${golden}/transcript.jsonl`;
    const file = Bun.file(transcriptPath);

    if (!(await file.exists())) {
      continue;
    }

    try {
      const stats = await processTranscript(transcriptPath);
      totalPathsReplaced += stats.pathsReplaced;
      totalBytesSaved += stats.before - stats.after;

      const reduction = stats.before > 0 ? Math.round((1 - stats.after / stats.before) * 100) : 0;
      console.log(`✓ ${golden}`);
      console.log(`  Paths replaced: ${stats.pathsReplaced}`);
      console.log(`  Size: ${stats.before} → ${stats.after} bytes (${reduction}% reduction)`);
    } catch (err) {
      console.log(`✗ ${golden}: ${err}`);
    }
  }

  console.log("\n--- Summary ---");
  console.log(`Total paths sanitized: ${totalPathsReplaced}`);
  console.log(`Total bytes saved: ${totalBytesSaved}`);
}

main().catch(console.error);
