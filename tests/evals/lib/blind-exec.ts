#!/usr/bin/env bun

/**
 * Blind Execution Test
 *
 * Validates that an enhanced prompt can be executed by a cheap model (Haiku)
 * to produce syntactically valid code.
 *
 * Usage:
 *   bun blind-exec.ts <enhanced-prompt-file>
 *   bun blind-exec.ts tests/evals/enhance/outputs/01-create-script.enhanced.md
 */

import { $ } from "bun";

interface BlindExecResult {
  promptFile: string;
  codeGenerated: boolean;
  syntaxValid: boolean;
  language: string | null;
  error: string | null;
  codeSnippet: string | null;
}

/**
 * Extract code blocks from Haiku's response
 */
function extractCodeBlocks(response: string): Array<{ lang: string; code: string }> {
  const blocks: Array<{ lang: string; code: string }> = [];
  const pattern = /```(\w+)?\n([\s\S]*?)```/g;

  for (const match of response.matchAll(pattern)) {
    blocks.push({
      lang: match[1] || "unknown",
      code: match[2].trim(),
    });
  }
  return blocks;
}

/**
 * Run syntax check for TypeScript/JavaScript
 */
async function checkTsSyntax(code: string): Promise<{ valid: boolean; error?: string }> {
  const tempFile = `/tmp/blind-exec-${Date.now()}.ts`;
  await Bun.write(tempFile, code);

  try {
    // Use bun to check TypeScript syntax
    const result = await $`bun build ${tempFile} --no-bundle 2>&1`.quiet();
    await $`rm -f ${tempFile}`.quiet();
    return { valid: true };
  } catch (e: any) {
    await $`rm -f ${tempFile}`.quiet();
    return { valid: false, error: e.message || "Syntax error" };
  }
}

/**
 * Run syntax check for Bash
 */
async function checkBashSyntax(code: string): Promise<{ valid: boolean; error?: string }> {
  const tempFile = `/tmp/blind-exec-${Date.now()}.sh`;
  await Bun.write(tempFile, code);

  try {
    await $`bash -n ${tempFile} 2>&1`.quiet();
    await $`rm -f ${tempFile}`.quiet();
    return { valid: true };
  } catch (e: any) {
    await $`rm -f ${tempFile}`.quiet();
    return { valid: false, error: e.message || "Syntax error" };
  }
}

/**
 * Run blind execution test on an enhanced prompt
 */
async function runBlindExec(promptFile: string): Promise<BlindExecResult> {
  const prompt = await Bun.file(promptFile).text();

  // Ask Haiku to generate code based on the enhanced prompt
  const systemPrompt = `You are a coding assistant. Given a task description, generate the code to implement it.
Output ONLY code in a single fenced code block with the appropriate language tag (typescript, bash, etc).
Do not include explanations, just the code.`;

  const userPrompt = `Generate the main implementation code for this task:\n\n${prompt}`;

  try {
    // Call Haiku via Claude CLI with heredoc for proper quoting
    const fullPrompt = `${systemPrompt}\n\n${userPrompt}`;
    const result = await $`claude --model haiku --print -p ${fullPrompt} 2>/dev/null`.text();

    const blocks = extractCodeBlocks(result);
    if (blocks.length === 0) {
      return {
        promptFile,
        codeGenerated: false,
        syntaxValid: false,
        language: null,
        error: "No code blocks in response",
        codeSnippet: result.slice(0, 200),
      };
    }

    // Check syntax of first code block
    const block = blocks[0];
    let syntaxResult: { valid: boolean; error?: string };

    if (block.lang === "typescript" || block.lang === "ts" || block.lang === "javascript" || block.lang === "js") {
      syntaxResult = await checkTsSyntax(block.code);
    } else if (block.lang === "bash" || block.lang === "sh" || block.lang === "shell") {
      syntaxResult = await checkBashSyntax(block.code);
    } else {
      // Unknown language - assume valid if we got code
      syntaxResult = { valid: true };
    }

    return {
      promptFile,
      codeGenerated: true,
      syntaxValid: syntaxResult.valid,
      language: block.lang,
      error: syntaxResult.error || null,
      codeSnippet: block.code.slice(0, 200),
    };
  } catch (e: any) {
    return {
      promptFile,
      codeGenerated: false,
      syntaxValid: false,
      language: null,
      error: e.message || "Failed to call Haiku",
      codeSnippet: null,
    };
  }
}

function formatResult(result: BlindExecResult): string {
  const lines: string[] = [];
  const status = result.syntaxValid ? "✓ PASS" : "✗ FAIL";

  lines.push(`\n## Blind Execution: ${status}\n`);
  lines.push(`  Code generated: ${result.codeGenerated ? "Yes" : "No"}`);
  if (result.language) {
    lines.push(`  Language: ${result.language}`);
  }
  lines.push(`  Syntax valid: ${result.syntaxValid ? "Yes" : "No"}`);
  if (result.error) {
    lines.push(`  Error: ${result.error}`);
  }

  return lines.join("\n");
}

// CLI
if (import.meta.main) {
  const args = process.argv.slice(2);

  if (args.length < 1) {
    console.log(`Usage: blind-exec.ts <enhanced-prompt-file>

Run blind execution test: give prompt to Haiku, check if generated code is syntactically valid.

Example:
  bun tests/evals/lib/blind-exec.ts tests/evals/enhance/outputs/01-create-script.enhanced.md`);
    process.exit(1);
  }

  const promptFile = args[0];
  const result = await runBlindExec(promptFile);
  console.log(formatResult(result));

  if (args.includes("--json")) {
    console.log("\n---\n");
    console.log(JSON.stringify(result, null, 2));
  }

  process.exit(result.syntaxValid ? 0 : 1);
}

export { runBlindExec, BlindExecResult };
