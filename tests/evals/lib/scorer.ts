#!/usr/bin/env bun

/**
 * Enhance Agent Output Scorer
 *
 * Measures quality of enhanced prompts across 4 dimensions:
 * - Groundedness: File paths and symbols actually exist
 * - Specificity: Concrete references (line numbers, code blocks, symbols)
 * - Information Gain: Symbol count delta from input to output
 * - Actionability: Imperative verbs + testable acceptance criteria
 */

import { existsSync } from "fs";
import { join } from "path";

// ============================================================================
// Types
// ============================================================================

export interface GroundednessScore {
  pathsFound: string[];
  pathsValid: string[];
  pathsInvalid: string[];
  symbolsFound: Array<{ symbol: string; file: string }>;
  symbolsValid: Array<{ symbol: string; file: string }>;
  score: number;
}

export interface SpecificityScore {
  lineNumberCount: number;
  codeBlockCount: number;
  symbolCount: number;
  score: number;
}

export interface InformationGainScore {
  inputSymbols: string[];
  outputSymbols: string[];
  newSymbols: string[];
  delta: number;
  score: number;
}

export interface ActionabilityScore {
  imperativeVerbCount: number;
  hasTestableAcceptance: boolean;
  acceptancePatterns: string[];
  score: number;
}

export interface EnhanceScore {
  groundedness: GroundednessScore;
  specificity: SpecificityScore;
  informationGain: InformationGainScore;
  actionability: ActionabilityScore;
  overall: number;
}

// ============================================================================
// Extraction Helpers
// ============================================================================

/**
 * Extract paths that are marked as TO_CREATE (should not exist yet)
 * Matches patterns like: "Create new file: `path`", "Create `path`", "Step 1: Create `path`"
 */
function extractToCreatePaths(text: string): Set<string> {
  const patterns = [
    // "Create new file: `path`", "Create file: `path`", "Create new test file (optional): `path`"
    /[Cc]reate(?:\s+new)?(?:\s+(?:test\s+)?file)?(?:\s+\(optional\))?[:\s]+`([^`]+)`/g,
    // "Create new test: `path`", "Create test: `path`"
    /[Cc]reate(?:\s+new)?(?:\s+test)[:\s]+`([^`]+)`/g,
    // "Step 1: Create `path`"
    /[Ss]tep\s+\d+[:\s]+[Cc]reate\s+`([^`]+)`/g,
    // "**Create**: `path`" or "**Create** `path`"
    /\*\*[Cc]reate\*\*[:\s]+`([^`]+)`/g,
    // "New file: `path`"
    /[Nn]ew\s+file[:\s]+`([^`]+)`/g,
    // "Create and pass new test: `path`"
    /[Cc]reate\s+and\s+pass\s+new\s+test[:\s]+`([^`]+)`/g,
  ];

  const toCreate = new Set<string>();
  for (const pattern of patterns) {
    for (const match of text.matchAll(pattern)) {
      toCreate.add(match[1].trim());
    }
  }
  return toCreate;
}

/**
 * Extract file paths from text
 * Matches: /path/to/file.ts, src/foo/bar.js, lib/something.sh, etc.
 */
function extractFilePaths(text: string): string[] {
  const patterns = [
    /(?:^|\s|`)((?:\/[\w.-]+)+\.[\w]+)/gm, // Absolute paths
    /(?:^|\s|`)((?:[\w.-]+\/)+[\w.-]+\.[\w]+)/gm, // Relative paths
  ];

  const paths = new Set<string>();
  for (const pattern of patterns) {
    for (const match of text.matchAll(pattern)) {
      const path = match[1].trim();
      // Filter out obvious non-paths
      if (!path.includes("http") && !path.startsWith(".")) {
        paths.add(path);
      }
    }
  }
  return Array.from(paths);
}

/**
 * Extract symbols (CamelCase, snake_case, SCREAMING_SNAKE)
 * These are likely function names, class names, constants
 */
function extractSymbols(text: string): string[] {
  const patterns = [
    /\b([A-Z][a-z]+(?:[A-Z][a-z]+)+)\b/g, // CamelCase
    /\b([a-z]+(?:_[a-z]+)+)\b/g, // snake_case
    /\b([A-Z]+(?:_[A-Z]+)+)\b/g, // SCREAMING_SNAKE
    /\b([a-z]+[A-Z][a-zA-Z]*)\b/g, // camelCase
  ];

  const symbols = new Set<string>();
  for (const pattern of patterns) {
    for (const match of text.matchAll(pattern)) {
      const symbol = match[1];
      // Filter out common words
      if (symbol.length > 3 && !isCommonWord(symbol)) {
        symbols.add(symbol);
      }
    }
  }
  return Array.from(symbols);
}

const COMMON_WORDS = new Set([
  "This",
  "That",
  "When",
  "Then",
  "From",
  "With",
  "Into",
  "Done",
  "Make",
  "Create",
  "Update",
  "Delete",
]);

function isCommonWord(word: string): boolean {
  return COMMON_WORDS.has(word);
}

/**
 * Extract symbol-file pairs from text
 * Looks for patterns like: `functionName` in `path/to/file.ts`
 */
function extractSymbolFilePairs(
  text: string
): Array<{ symbol: string; file: string }> {
  const pairs: Array<{ symbol: string; file: string }> = [];

  // Pattern: `symbol` in `file` or symbol in file.ext
  const pattern =
    /`?(\w+)`?\s+(?:in|from|at)\s+`?([\w./]+\.[\w]+)`?/gi;
  for (const match of text.matchAll(pattern)) {
    pairs.push({ symbol: match[1], file: match[2] });
  }

  return pairs;
}

/**
 * Count line number references
 * Matches: line 42, lines 10-20, :45, L123
 */
function countLineNumbers(text: string): number {
  const patterns = [
    /line\s*\d+/gi,
    /lines?\s*\d+\s*-\s*\d+/gi,
    /:\d+/g,
    /L\d+/g,
  ];

  let count = 0;
  for (const pattern of patterns) {
    const matches = text.match(pattern);
    if (matches) count += matches.length;
  }
  return count;
}

/**
 * Count code blocks
 */
function countCodeBlocks(text: string): number {
  const matches = text.match(/```[\s\S]*?```/g);
  return matches ? matches.length : 0;
}

/**
 * Count imperative verbs (action words)
 */
function countImperativeVerbs(text: string): number {
  const verbs = [
    "add",
    "create",
    "update",
    "delete",
    "remove",
    "modify",
    "change",
    "implement",
    "refactor",
    "fix",
    "move",
    "rename",
    "extract",
    "replace",
    "ensure",
    "verify",
    "check",
    "validate",
    "test",
    "run",
    "execute",
    "install",
    "configure",
    "set",
    "use",
    "call",
    "import",
    "export",
  ];

  let count = 0;
  const lowerText = text.toLowerCase();
  for (const verb of verbs) {
    const pattern = new RegExp(`\\b${verb}\\b`, "gi");
    const matches = lowerText.match(pattern);
    if (matches) count += matches.length;
  }
  return count;
}

/**
 * Check for testable acceptance criteria
 */
function findAcceptancePatterns(text: string): string[] {
  const patterns = [
    /done\s+when[^.]+\./gi,
    /success\s+looks\s+like[^.]+\./gi,
    /verify\s+by[^.]+\./gi,
    /acceptance\s+criteria[^.]+\./gi,
    /should\s+(?:return|output|produce)[^.]+\./gi,
  ];

  const found: string[] = [];
  for (const pattern of patterns) {
    const matches = text.match(pattern);
    if (matches) found.push(...matches);
  }
  return found;
}

// ============================================================================
// Validation Helpers
// ============================================================================

/**
 * Check if a file path exists relative to project root OR as absolute path
 */
function validatePath(path: string, projectRoot: string): boolean {
  // For absolute paths, check if they exist directly
  if (path.startsWith("/")) {
    if (existsSync(path)) return true;
    // Also try relative to project root (without leading slash)
    return existsSync(join(projectRoot, path.slice(1)));
  }
  // For relative paths, check relative to project root
  return existsSync(join(projectRoot, path));
}

/**
 * Check if a symbol exists in a file using grep
 */
async function validateSymbol(
  symbol: string,
  file: string,
  projectRoot: string
): Promise<boolean> {
  const fullPath = join(projectRoot, file);
  if (!existsSync(fullPath)) return false;

  try {
    const content = await Bun.file(fullPath).text();
    return content.includes(symbol);
  } catch {
    return false;
  }
}

// ============================================================================
// Scoring Functions
// ============================================================================

async function scoreGroundedness(
  output: string,
  projectRoot: string
): Promise<GroundednessScore> {
  const allPaths = extractFilePaths(output);
  const toCreatePaths = extractToCreatePaths(output);

  // Filter out TO_CREATE paths - they're expected to not exist
  const pathsFound = allPaths.filter(p => !toCreatePaths.has(p));
  const pathsValid: string[] = [];
  const pathsInvalid: string[] = [];

  for (const path of pathsFound) {
    if (validatePath(path, projectRoot)) {
      pathsValid.push(path);
    } else {
      pathsInvalid.push(path);
    }
  }

  const symbolsFound = extractSymbolFilePairs(output);
  const symbolsValid: Array<{ symbol: string; file: string }> = [];

  for (const { symbol, file } of symbolsFound) {
    if (await validateSymbol(symbol, file, projectRoot)) {
      symbolsValid.push({ symbol, file });
    }
  }

  // Score: weight paths more heavily than symbols
  const pathScore =
    pathsFound.length > 0 ? pathsValid.length / pathsFound.length : 1;
  const symbolScore =
    symbolsFound.length > 0
      ? symbolsValid.length / symbolsFound.length
      : 1;

  return {
    pathsFound,
    pathsValid,
    pathsInvalid,
    symbolsFound,
    symbolsValid,
    score: pathScore * 0.7 + symbolScore * 0.3,
  };
}

function scoreSpecificity(output: string): SpecificityScore {
  const lineNumberCount = countLineNumbers(output);
  const codeBlockCount = countCodeBlocks(output);
  const symbolCount = extractSymbols(output).length;

  // Normalize to 0-1 (diminishing returns after thresholds)
  const lineScore = Math.min(lineNumberCount / 5, 1);
  const codeScore = Math.min(codeBlockCount / 3, 1);
  const symbolScore = Math.min(symbolCount / 10, 1);

  return {
    lineNumberCount,
    codeBlockCount,
    symbolCount,
    score: (lineScore + codeScore + symbolScore) / 3,
  };
}

function scoreInformationGain(
  input: string,
  output: string
): InformationGainScore {
  const inputSymbols = extractSymbols(input);
  const outputSymbols = extractSymbols(output);

  // Find symbols in output that weren't in input
  const inputSet = new Set(inputSymbols);
  const newSymbols = outputSymbols.filter((s) => !inputSet.has(s));

  const delta = newSymbols.length;

  // Score: normalize with diminishing returns
  const score = Math.min(delta / 15, 1);

  return {
    inputSymbols,
    outputSymbols,
    newSymbols,
    delta,
    score,
  };
}

function scoreActionability(output: string): ActionabilityScore {
  const imperativeVerbCount = countImperativeVerbs(output);
  const acceptancePatterns = findAcceptancePatterns(output);
  const hasTestableAcceptance = acceptancePatterns.length > 0;

  // Score: verbs + acceptance criteria
  const verbScore = Math.min(imperativeVerbCount / 10, 1);
  const acceptanceScore = hasTestableAcceptance ? 1 : 0;

  return {
    imperativeVerbCount,
    hasTestableAcceptance,
    acceptancePatterns,
    score: verbScore * 0.6 + acceptanceScore * 0.4,
  };
}

// ============================================================================
// Main Scoring Function
// ============================================================================

export async function scoreEnhancedPrompt(
  input: string,
  output: string,
  projectRoot: string
): Promise<EnhanceScore> {
  const groundedness = await scoreGroundedness(output, projectRoot);
  const specificity = scoreSpecificity(output);
  const informationGain = scoreInformationGain(input, output);
  const actionability = scoreActionability(output);

  // GROUNDEDNESS IS A GATE: If any invalid paths, overall score = 0
  // This prevents rewarding prompts that hallucinate file paths
  const groundednessPass = groundedness.pathsInvalid.length === 0;

  // Weighted score (only if groundedness passes)
  // Dropped Information Gain per second opinion (rewards verbosity, not quality)
  // New weights: Specificity 40%, Actionability 60%
  const overall = groundednessPass
    ? specificity.score * 0.4 + actionability.score * 0.6
    : 0;

  return {
    groundedness,
    specificity,
    informationGain,
    actionability,
    overall,
  };
}

// ============================================================================
// CLI
// ============================================================================

function formatScore(score: EnhanceScore): string {
  const lines: string[] = [];
  const groundednessPass = score.groundedness.pathsInvalid.length === 0;

  lines.push(`\n## Overall Score: ${(score.overall * 100).toFixed(1)}%\n`);

  // Groundedness is a GATE - show pass/fail status
  const gateStatus = groundednessPass ? "✓ PASS" : "✗ FAIL (score zeroed)";
  lines.push(`### Groundedness Gate: ${gateStatus}`);
  lines.push(`  Paths: ${score.groundedness.pathsValid.length}/${score.groundedness.pathsFound.length} valid`);
  if (score.groundedness.pathsInvalid.length > 0) {
    lines.push(`  Invalid: ${score.groundedness.pathsInvalid.join(", ")}`);
  }
  lines.push(`  Symbols: ${score.groundedness.symbolsValid.length}/${score.groundedness.symbolsFound.length} verified`);

  lines.push(`\n### Specificity (40%): ${(score.specificity.score * 100).toFixed(1)}%`);
  lines.push(`  Line numbers: ${score.specificity.lineNumberCount}`);
  lines.push(`  Code blocks: ${score.specificity.codeBlockCount}`);
  lines.push(`  Symbols: ${score.specificity.symbolCount}`);

  // Information Gain shown for reference but not weighted
  lines.push(`\n### Information Gain (not weighted): +${score.informationGain.delta} symbols`);

  lines.push(`\n### Actionability (60%): ${(score.actionability.score * 100).toFixed(1)}%`);
  lines.push(`  Imperative verbs: ${score.actionability.imperativeVerbCount}`);
  lines.push(`  Testable acceptance: ${score.actionability.hasTestableAcceptance ? "Yes" : "No"}`);
  if (score.actionability.acceptancePatterns.length > 0) {
    lines.push(`  Patterns found: ${score.actionability.acceptancePatterns.length}`);
  }

  return lines.join("\n");
}

if (import.meta.main) {
  const args = process.argv.slice(2);

  if (args.length < 2) {
    console.log(`Usage: scorer.ts <input-file> <output-file> [project-root]

Score an enhanced prompt output against the original input.

Arguments:
  input-file    Path to original rough prompt
  output-file   Path to enhanced prompt output
  project-root  Project root for path validation (default: cwd)

Example:
  bun tests/evals/lib/scorer.ts \\
    tests/evals/enhance/cases/05-add-validation.txt \\
    tests/evals/enhance/outputs/05-add-validation.enhanced.md`);
    process.exit(1);
  }

  const inputFile = args[0];
  const outputFile = args[1];
  const projectRoot = args[2] || process.cwd();

  try {
    const input = await Bun.file(inputFile).text();
    const output = await Bun.file(outputFile).text();

    const score = await scoreEnhancedPrompt(input, output, projectRoot);
    console.log(formatScore(score));

    // Output JSON for programmatic use
    if (args.includes("--json")) {
      console.log("\n---\n");
      console.log(JSON.stringify(score, null, 2));
    }
  } catch (error) {
    console.error(`Error: ${(error as Error).message}`);
    process.exit(1);
  }
}
