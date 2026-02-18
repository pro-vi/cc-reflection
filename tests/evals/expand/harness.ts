#!/usr/bin/env bun
/**
 * Expand Agent Eval Harness
 *
 * Evaluates expand agent output quality using LLM-as-Judge.
 *
 * Usage:
 *   bun harness.ts <case>              Show golden case details
 *   bun harness.ts --run <case>        Run eval on one case
 *   bun harness.ts --run --all         Run all golden cases
 *   bun harness.ts --run --all --save  Run all and save results
 */

import { readdirSync, readFileSync, existsSync } from "fs";
import { join, dirname } from "path";
import { execSync } from "child_process";

import { callOpenRouter } from "./lib/openrouter";
import {
  type ReflectionSeed,
  type ExpandGolden,
  type ExpandEvalScore,
  scoreExpandWithJudge,
  computeSummary,
} from "./lib/scorer";
import {
  type ExpandEvalReport,
  formatTable,
  formatVerbose,
  saveReport,
} from "./lib/reporter";

// ============================================================================
// Constants
// ============================================================================

const SCRIPT_DIR = dirname(new URL(import.meta.url).pathname);
const GOLDEN_DIR = join(SCRIPT_DIR, "golden");
const RESULTS_DIR = join(SCRIPT_DIR, "results");
const PROJECT_ROOT = join(SCRIPT_DIR, "../../..");

// Default model for expansion generation
const EVAL_MODEL = "anthropic/claude-3.5-sonnet";

// ============================================================================
// Golden Case Loading
// ============================================================================

/**
 * List all available golden cases
 */
function listGoldenCases(): string[] {
  if (!existsSync(GOLDEN_DIR)) return [];
  return readdirSync(GOLDEN_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name);
}

/**
 * Load a golden case by name
 */
function loadGolden(caseName: string): ExpandGolden {
  const dir = join(GOLDEN_DIR, caseName);

  if (!existsSync(dir)) {
    throw new Error(`Golden case not found: ${caseName}`);
  }

  const seedPath = join(dir, "seed.json");
  const expansionPath = join(dir, "expansion.md");
  const metaPath = join(dir, "meta.json");

  if (!existsSync(seedPath)) {
    throw new Error(`Missing seed.json in ${caseName}`);
  }
  if (!existsSync(expansionPath)) {
    throw new Error(`Missing expansion.md in ${caseName}`);
  }

  const seed: ReflectionSeed = JSON.parse(readFileSync(seedPath, "utf-8"));
  const referenceExpansion = readFileSync(expansionPath, "utf-8");
  const meta = existsSync(metaPath)
    ? JSON.parse(readFileSync(metaPath, "utf-8"))
    : { name: caseName, description: "", why_its_good: [], focus_areas: [] };

  return { seed, referenceExpansion, meta };
}

// ============================================================================
// Prompt Generation
// ============================================================================

/**
 * Generate the expand system prompt using bash prompt-builder
 */
function generateExpandPrompt(outputFile: string): string {
  try {
    const result = execSync(
      `cd "${PROJECT_ROOT}" && source lib/prompt-builder.sh && build_system_prompt expand-auto "${outputFile}"`,
      { encoding: "utf-8", shell: "/bin/bash" }
    );
    return result;
  } catch (error) {
    throw new Error(`Failed to generate expand prompt: ${(error as Error).message}`);
  }
}

/**
 * Build full prompt with seed
 */
function buildFullPrompt(systemPrompt: string, seed: ReflectionSeed): string {
  return `${systemPrompt}

## Seed to Expand

\`\`\`json
${JSON.stringify(seed, null, 2)}
\`\`\`

Now investigate this seed and write your expansion. Remember: your session succeeds when the output file contains your expansion.`;
}

// ============================================================================
// Evaluation
// ============================================================================

/**
 * Run evaluation on a single golden case
 */
async function runExpandEval(
  caseName: string,
  model: string = EVAL_MODEL,
  verbose: boolean = false
): Promise<ExpandEvalScore> {
  const golden = loadGolden(caseName);

  if (verbose) {
    console.log(`\n[${caseName}] Loading golden case...`);
    console.log(`  Seed: ${golden.seed.title}`);
    console.log(`  Reference: ${golden.referenceExpansion.length} chars`);
  }

  // Generate expand prompt
  const outputFile = `/tmp/expand-eval-${caseName}.md`;
  const systemPrompt = generateExpandPrompt(outputFile);
  const fullPrompt = buildFullPrompt(systemPrompt, golden.seed);

  if (verbose) {
    console.log(`  Prompt: ${fullPrompt.length} chars`);
    console.log(`  Calling ${model}...`);
  }

  // Call model
  const startTime = Date.now();
  const response = await callOpenRouter(fullPrompt, model);
  const latencyMs = Date.now() - startTime;

  if (response.error) {
    console.error(`  Error: ${response.error}`);
    return {
      caseName,
      model,
      promptTokens: response.promptTokens,
      completionTokens: response.completionTokens,
      latencyMs,
      response: "",
      error: response.error,
    };
  }

  if (verbose) {
    console.log(`  Response: ${response.content.length} chars (${response.completionTokens} tokens)`);
    console.log(`  Scoring with judge...`);
  }

  // Score with judge
  const judgeResult = await scoreExpandWithJudge(
    golden.seed,
    response.content,
    golden.referenceExpansion
  );

  if (verbose) {
    console.log(`  Overall: ${(judgeResult.overall * 100).toFixed(1)}%`);
    console.log(`  Rationale: ${judgeResult.rationale}`);
  }

  return {
    caseName,
    model,
    judgeResult,
    promptTokens: response.promptTokens,
    completionTokens: response.completionTokens,
    latencyMs,
    response: response.content,
  };
}

/**
 * Run evaluation on all golden cases
 */
async function runAllEvals(
  model: string = EVAL_MODEL,
  verbose: boolean = false
): Promise<ExpandEvalScore[]> {
  const cases = listGoldenCases();
  if (cases.length === 0) {
    console.log("No golden cases found in", GOLDEN_DIR);
    return [];
  }

  console.log(`Running ${cases.length} golden cases with ${model}...\n`);

  const results: ExpandEvalScore[] = [];
  for (const caseName of cases) {
    try {
      const result = await runExpandEval(caseName, model, verbose);
      results.push(result);
    } catch (error) {
      console.error(`Error in ${caseName}: ${(error as Error).message}`);
      results.push({
        caseName,
        model,
        promptTokens: 0,
        completionTokens: 0,
        latencyMs: 0,
        response: "",
        error: (error as Error).message,
      });
    }
  }

  return results;
}

// ============================================================================
// CLI
// ============================================================================

function printUsage(): void {
  console.log(`Expand Agent Eval Harness

Usage:
  bun harness.ts                        List available golden cases
  bun harness.ts <case>                 Show golden case details
  bun harness.ts --run <case>           Run eval on one case
  bun harness.ts --run --all            Run all golden cases
  bun harness.ts --run --all --save     Run all and save results
  bun harness.ts --run --all --verbose  Run all with detailed output

Options:
  --model <model>   Model to use (default: ${EVAL_MODEL})
  --verbose         Show detailed output during evaluation
  --save            Save results to results/ directory
`);
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    // List golden cases
    const cases = listGoldenCases();
    if (cases.length === 0) {
      console.log("No golden cases found.");
      console.log(`Create cases in: ${GOLDEN_DIR}`);
    } else {
      console.log("Available golden cases:");
      for (const c of cases) {
        console.log(`  - ${c}`);
      }
    }
    return;
  }

  const isRun = args.includes("--run");
  const isAll = args.includes("--all");
  const isSave = args.includes("--save");
  const isVerbose = args.includes("--verbose");

  // Extract model option
  const modelIdx = args.indexOf("--model");
  const model = modelIdx !== -1 && args[modelIdx + 1] ? args[modelIdx + 1] : EVAL_MODEL;

  // Extract case name (first arg that doesn't start with --)
  const caseName = args.find((a) => !a.startsWith("--") && a !== model);

  if (!isRun) {
    // Show golden case details
    if (!caseName) {
      printUsage();
      return;
    }

    try {
      const golden = loadGolden(caseName);
      console.log(`\n## Golden Case: ${caseName}\n`);
      console.log(`**Seed Title**: ${golden.seed.title}`);
      console.log(`**Seed ID**: ${golden.seed.id}`);
      console.log(`\n**Rationale**:\n${golden.seed.rationale.slice(0, 500)}...`);
      console.log(`\n**Anchors**: ${golden.seed.anchors.length}`);
      for (const a of golden.seed.anchors) {
        console.log(`  - ${a.path}`);
      }
      console.log(`\n**Reference Expansion**: ${golden.referenceExpansion.length} chars`);
      console.log(`\n**Meta**:`);
      console.log(`  Why it's good: ${golden.meta.why_its_good.join(", ")}`);
      console.log(`  Focus areas: ${golden.meta.focus_areas.join(", ")}`);
    } catch (error) {
      console.error(`Error: ${(error as Error).message}`);
      process.exit(1);
    }
    return;
  }

  // Run evaluation
  if (isAll) {
    const results = await runAllEvals(model, isVerbose);
    const summary = computeSummary(results);

    console.log("\n" + formatTable(results, summary));

    if (isSave) {
      const report: ExpandEvalReport = {
        timestamp: new Date().toISOString(),
        model,
        results,
        summary,
      };
      const filepath = await saveReport(report, RESULTS_DIR);
      console.log(`\nResults saved to: ${filepath}`);
    }
  } else if (caseName) {
    try {
      const result = await runExpandEval(caseName, model, isVerbose);
      console.log("\n" + formatVerbose(result));
    } catch (error) {
      console.error(`Error: ${(error as Error).message}`);
      process.exit(1);
    }
  } else {
    console.error("Error: Specify a case name or use --all");
    printUsage();
    process.exit(1);
  }
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
