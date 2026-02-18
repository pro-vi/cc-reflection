#!/usr/bin/env bun

/**
 * Transcript reading — reflection-specific
 *
 * Provides recent turns extraction for expand prompt context.
 * Transcript path resolution and exchange counting have moved to cc-dice.
 */

// ============================================================================
// Recent Turns Extraction
// ============================================================================

/**
 * Content block types in Claude Code transcripts
 */
interface TextBlock {
  type: "text";
  text: string;
}

interface ToolUseBlock {
  type: "tool_use";
  id: string;
  name: string;
  input: unknown;
}

interface ToolResultBlock {
  type: "tool_result";
  tool_use_id: string;
  content: unknown;
}

interface ThinkingBlock {
  type: "thinking";
  thinking: string;
}

type ContentBlock = TextBlock | ToolUseBlock | ToolResultBlock | ThinkingBlock | { type: string };

/**
 * Transcript entry structure
 */
interface TranscriptEntry {
  type: "user" | "assistant" | "system" | "file-history-snapshot" | string;
  message?: {
    role?: string;
    content?: string | ContentBlock[];
  };
}

/**
 * Extract text content from a transcript entry
 *
 * Filtering rules:
 * - Include: user text (string content), assistant text blocks
 * - Exclude: tool_use, tool_result, thinking, system, file-history-snapshot
 */
function extractTextContent(entry: TranscriptEntry): { role: "user" | "assistant"; text: string } | null {
  // Skip non-message types
  if (entry.type === "system" || entry.type === "file-history-snapshot") {
    return null;
  }

  // Skip entries without message
  if (!entry.message) return null;

  const role = entry.type === "user" ? "user" : entry.type === "assistant" ? "assistant" : null;
  if (!role) return null;

  const content = entry.message.content;
  if (!content) return null;

  // User messages: content is usually a string
  if (typeof content === "string") {
    const trimmed = content.trim();
    if (trimmed.length === 0) return null;
    return { role, text: trimmed };
  }

  // Assistant messages: content is array of blocks, extract text blocks only
  if (Array.isArray(content)) {
    const textParts: string[] = [];
    for (const block of content) {
      if (block.type === "text" && "text" in block && typeof block.text === "string") {
        const trimmed = block.text.trim();
        if (trimmed.length > 0) {
          textParts.push(trimmed);
        }
      }
      // Skip: tool_use, tool_result, thinking blocks
    }
    if (textParts.length === 0) return null;
    return { role, text: textParts.join("\n\n") };
  }

  return null;
}

/**
 * Get recent conversation turns from a transcript file
 *
 * Optimized for large files using tail-read approach:
 * - Reads last 256KB of file (sufficient for ~100+ turns)
 * - Filters to user/assistant text only
 * - Returns last N turns
 *
 * @param transcriptPath - Path to transcript JSONL file
 * @param n - Number of recent turns to return
 * @returns Array of formatted turn strings (e.g., "User: ...", "Assistant: ...")
 */
export async function getRecentTurns(transcriptPath: string, n: number): Promise<string[]> {
  if (n <= 0) return [];

  try {
    const file = Bun.file(transcriptPath);
    if (!(await file.exists())) return [];

    const fileSize = file.size;
    const CHUNK_SIZE = 256 * 1024; // 256KB
    const LARGE_CHUNK_SIZE = 1024 * 1024; // 1MB fallback

    /**
     * Read and parse a chunk of the transcript file
     * @param chunkSize - Size of chunk to read from end of file
     * @returns Array of extracted turns
     */
    const readChunk = async (chunkSize: number): Promise<string[]> => {
      let content: string;

      if (fileSize <= chunkSize) {
        // File fits in chunk: read all
        content = await file.text();
      } else {
        // Read last chunk
        // Note: We may get a partial first line, which we'll handle
        const buffer = await file.slice(fileSize - chunkSize, fileSize).arrayBuffer();
        content = new TextDecoder().decode(buffer);
        // Skip first (potentially partial) line
        const firstNewline = content.indexOf("\n");
        if (firstNewline > 0) {
          content = content.slice(firstNewline + 1);
        }
      }

      const lines = content.trim().split("\n").filter(Boolean);
      const turns: string[] = [];

      for (const line of lines) {
        try {
          const entry: TranscriptEntry = JSON.parse(line);
          const extracted = extractTextContent(entry);
          if (extracted) {
            const prefix = extracted.role === "user" ? "User" : "Assistant";
            turns.push(`${prefix}: ${extracted.text}`);
          }
        } catch {
          // Skip malformed lines
        }
      }

      return turns;
    };

    // First attempt with standard chunk
    let turns = await readChunk(CHUNK_SIZE);

    // Fallback: if no turns found and file is larger than chunk,
    // retry with larger chunk (handles 256KB+ tool outputs)
    if (turns.length === 0 && fileSize > CHUNK_SIZE) {
      turns = await readChunk(LARGE_CHUNK_SIZE);
    }

    // Return last N turns
    return turns.slice(-n);
  } catch {
    return [];
  }
}
