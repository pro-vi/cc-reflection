#!/usr/bin/env bun
/**
 * Reflection Eval Harness
 *
 * Tests if models can identify golden seeds from transcripts using the SKILL.md prompt.
 * Uses LLM-as-Judge semantic scoring.
 *
 * Usage:
 *   # Prompt generation (manual eval)
 *   bun harness.ts <golden-name>
 *
 *   # API-based eval (requires OPENROUTER_API_KEY)
 *   bun harness.ts --run <golden-name> [--model <model>]
 *   bun harness.ts --run --all
 *
 *   # Options
 *   --model <model>      Model to use (default: openai/gpt-4o-mini)
 *   --no-judge           Disable LLM-as-Judge (keyword scoring only)
 *   --output json        Output as JSON instead of table
 *   --verbose            Show full response for each eval
 *   --save               Save results to results/ directory
 *
 * Examples:
 *   bun harness.ts user-intervention-complexity
 *   bun harness.ts --run --all
 *   bun harness.ts --run --all --model google/gemini-flash-1.5 --save
 */

import { readFileSync, readdirSync, existsSync, mkdirSync } from "fs";
import { join } from "path";

// Load .env from script's directory (not cwd)
const envPath = join(import.meta.dir, ".env");
if (existsSync(envPath)) {
  const envContent = readFileSync(envPath, "utf-8");
  for (const line of envContent.split("\n")) {
    const trimmed = line.trim();
    if (trimmed && !trimmed.startsWith("#")) {
      const [key, ...valueParts] = trimmed.split("=");
      const value = valueParts.join("=");
      if (key && value && !process.env[key]) {
        process.env[key] = value;
      }
    }
  }
}

import { callOpenRouter, DEFAULT_MODEL } from "./lib/openrouter";
import { scoreResponse, scoreWithJudge, normalizeJudgeScore, computeSummary, type GoldenSeed, type EvalScore } from "./lib/scorer";
import { formatTable, formatJson, formatVerbose, saveReport, type EvalReport } from "./lib/reporter";

interface GoldenMeta {
  name: string;
  description: string;
  why_its_good: string[];
  transcript_signals: {
    engineering?: string[];
    product?: string[];
    meta?: string[];
  };
  expected_detection: {
    should_identify: string;
    should_cite: string;
    should_propose: string;
  };
  eval_criteria: {
    recall: string;
    precision: string;
    signal_detection: string;
  };
}

const GOLDEN_DIR = join(import.meta.dir, "golden");
const PROMPTS_DIR = join(import.meta.dir, "prompts");
const RESULTS_DIR = join(import.meta.dir, "results");

function loadSkillPrompt(): string {
  const path = join(PROMPTS_DIR, "skill.md");
  if (!existsSync(path)) {
    throw new Error(`Missing skill prompt: ${path}`);
  }
  return readFileSync(path, "utf-8");
}

function listGoldens(): string[] {
  if (!existsSync(GOLDEN_DIR)) return [];
  return readdirSync(GOLDEN_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name);
}

function loadGolden(name: string): {
  transcript: string;
  seed: GoldenSeed;
  meta: GoldenMeta;
} {
  const dir = join(GOLDEN_DIR, name);

  const transcriptPath = join(dir, "transcript.jsonl");
  const seedPath = join(dir, "golden-seed.json");
  const metaPath = join(dir, "meta.json");

  if (!existsSync(transcriptPath)) {
    throw new Error(`Missing transcript: ${transcriptPath}`);
  }
  if (!existsSync(seedPath)) {
    throw new Error(`Missing golden-seed: ${seedPath}`);
  }
  if (!existsSync(metaPath)) {
    throw new Error(`Missing meta: ${metaPath}`);
  }

  return {
    transcript: readFileSync(transcriptPath, "utf-8"),
    seed: JSON.parse(readFileSync(seedPath, "utf-8")),
    meta: JSON.parse(readFileSync(metaPath, "utf-8")),
  };
}

function extractCleanTranscript(jsonl: string): string {
  const lines = jsonl.trim().split("\n");
  const turns: string[] = [];

  for (const line of lines) {
    try {
      const entry = JSON.parse(line);
      if (entry.isSidechain) continue;

      if (entry.type === "user" || entry.type === "assistant") {
        const content = entry.message?.content;
        const prefix = entry.type.toUpperCase();

        if (typeof content === "string") {
          turns.push(`${prefix}: ${content.slice(0, 500)}`);
        } else if (Array.isArray(content)) {
          const text = content
            .filter((c: any) => c.type === "text")
            .map((c: any) => c.text)
            .join("\n");
          if (text) {
            turns.push(`${prefix}: ${text.slice(0, 500)}`);
          }
        }
      }

      // Include tool errors
      if (entry.toolUseResult?.stderr) {
        const stderr = entry.toolUseResult.stderr;
        if (stderr.length > 0) {
          turns.push(`TOOL_ERROR: ${stderr.slice(0, 300)}`);
        }
      }
    } catch {
      // Skip malformed lines
    }
  }

  return turns.slice(-50).join("\n\n");
}

function generatePrompt(cleanTranscript: string, skillPrompt: string): string {
  return `You are analyzing a conversation transcript for strategic insights worth capturing as reflection seeds.

## Your Skill Instructions

${skillPrompt}

---

## Transcript to Analyze

${cleanTranscript}

---

## Task

Apply your skill instructions to analyze this transcript. Identify reflection-worthy moments using the Three Examinations framework.

## Output Format

For each insight worth capturing, output:
- EXAMINATION: [first/second/third]
- TITLE: [category: brief description]
- EVIDENCE: [quote or paraphrase from transcript]
- RATIONALE: [why this matters, what should be done]

If no insights are worth capturing, output: NO_SEEDS (or 今日無省 if using the new skill)

Be ruthless - only capture non-obvious, reusable insights that would be lost without documentation.`;
}

// --- API-based eval functions ---

async function runSingleEval(
  goldenName: string,
  model: string,
  verbose: boolean,
  useJudge: boolean = false
): Promise<EvalScore> {
  const { transcript, seed } = loadGolden(goldenName);
  const cleanTranscript = extractCleanTranscript(transcript);
  const skillPrompt = loadSkillPrompt();
  const prompt = generatePrompt(cleanTranscript, skillPrompt);

  if (verbose) {
    console.log(`\nCalling ${model} for ${goldenName}...`);
  }

  const response = await callOpenRouter(prompt, model);

  const score = scoreResponse(
    response.content,
    goldenName,
    model,
    {
      promptTokens: response.promptTokens,
      completionTokens: response.completionTokens,
      latencyMs: response.latencyMs,
      error: response.error,
    }
  );

  // Add LLM-as-Judge scoring if requested
  if (useJudge && response.content) {
    if (verbose) {
      console.log(`  Running LLM-as-Judge...`);
    }
    const judgeResult = await scoreWithJudge(response.content, seed);
    score.judgeResult = judgeResult;
    score.judgeScore = normalizeJudgeScore(judgeResult.score);

    if (verbose && judgeResult.rationale) {
      console.log(`  Judge: ${judgeResult.score}/5 - ${judgeResult.rationale}`);
      if (judgeResult.isAdjacent) {
        console.log(`  (Adjacent insight detected)`);
      }
    }
  }

  if (verbose) {
    console.log(formatVerbose(score));
  }

  return score;
}

async function runEvals(
  goldens: string[],
  model: string,
  verbose: boolean,
  useJudge: boolean = false
) {
  const results: EvalScore[] = [];
  for (const golden of goldens) {
    const score = await runSingleEval(golden, model, verbose, useJudge);
    results.push(score);
  }
  return results;
}

// --- CLI ---

async function main() {
  const args = process.argv.slice(2);

  // Parse flags
  const hasRun = args.includes("--run");
  const hasAll = args.includes("--all");
  const verbose = args.includes("--verbose");
  const outputJson = args.includes("--output") && args[args.indexOf("--output") + 1] === "json";
  const shouldSave = args.includes("--save");
  const useJudge = !args.includes("--no-judge"); // Judge is default, --no-judge disables

  // Get model
  const modelIdx = args.indexOf("--model");
  const model = modelIdx !== -1 ? args[modelIdx + 1] : DEFAULT_MODEL;

  // Get golden name (first non-flag arg)
  const filteredArgs = args.filter(
    (a) => !a.startsWith("--") &&
           args[args.indexOf(a) - 1] !== "--model" &&
           args[args.indexOf(a) - 1] !== "--output"
  );
  const goldenName = filteredArgs[0];

  // List mode
  if (args.length === 0 || args[0] === "--list") {
    const goldens = listGoldens();
    console.log("Available golden seeds:");
    goldens.forEach((g) => console.log(`  - ${g}`));
    console.log("\nUsage:");
    console.log("  bun harness.ts <golden-name>                         # generate prompt");
    console.log("  bun harness.ts --run <golden-name> [--model <m>]     # run eval");
    console.log("  bun harness.ts --run --all [--model <m>] [--save]    # run all");
    process.exit(0);
  }

  // Determine which goldens to run
  const goldens = hasAll ? listGoldens() : goldenName ? [goldenName] : [];
  if (goldens.length === 0) {
    console.error("No golden specified. Use --all or provide a golden name.");
    process.exit(1);
  }

  // API-based eval mode
  if (hasRun) {
    if (!process.env.OPENROUTER_API_KEY) {
      console.error("OPENROUTER_API_KEY required for --run");
      console.error("Set it in your environment or .env file");
      process.exit(1);
    }

    console.log(`\n=== Reflection Eval ===`);
    console.log(`Model: ${model}`);
    console.log(`Goldens: ${goldens.join(", ")}${useJudge ? "" : " (keywords only)"}\n`);

    const results = await runEvals(goldens, model, verbose, useJudge);

    const summary = computeSummary(results);
    const report: EvalReport = {
      timestamp: new Date().toISOString(),
      model,
      results,
      summary,
    };

    // Output
    if (outputJson) {
      console.log(formatJson(report));
    } else {
      console.log("\n" + formatTable(results, summary));
    }

    // Save if requested
    if (shouldSave) {
      if (!existsSync(RESULTS_DIR)) {
        mkdirSync(RESULTS_DIR, { recursive: true });
      }
      const filepath = await saveReport(report, RESULTS_DIR);
      console.log(`\nResults saved to: ${filepath}`);
    }

    process.exit(0);
  }

  // Prompt generation mode (original behavior)
  console.log(`\n=== Reflection Eval: ${goldenName} ===\n`);

  try {
    const { transcript, seed, meta } = loadGolden(goldenName);
    const cleanTranscript = extractCleanTranscript(transcript);
    const skillPrompt = loadSkillPrompt();
    const prompt = generatePrompt(cleanTranscript, skillPrompt);

    console.log(`Transcript lines: ${transcript.split("\n").length}`);
    console.log(`Clean turns: ${cleanTranscript.split("\n\n").length}`);
    console.log(`Skill prompt size: ${skillPrompt.length} chars`);
    console.log(`Expected: ${meta.expected_detection.should_identify}`);
    if (seed.trigger) {
      console.log(`Trigger: ${seed.trigger}`);
    }
    console.log("\n--- Prompt Preview (first 800 chars) ---");
    console.log(prompt.slice(0, 800) + "...\n");

    console.log("--- Golden Seed ---");
    console.log(`Title: ${seed.title}`);
    console.log(`Examination: ${seed.examination}`);
    console.log(`Anchor: ${seed.anchor_file}`);

    console.log("\n--- To run eval with model ---");
    console.log(`bun harness.ts --run ${goldenName}\n`);

    // Output the full prompt to a file for manual testing
    const promptPath = join(GOLDEN_DIR, goldenName, "eval-prompt.txt");
    await Bun.write(promptPath, prompt);
    console.log(`Full prompt saved to: ${promptPath}`);
  } catch (err) {
    console.error(`Error: ${err}`);
    process.exit(1);
  }
}

main();
