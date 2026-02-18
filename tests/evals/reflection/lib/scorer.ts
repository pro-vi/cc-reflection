/**
 * Scoring logic for reflection evals
 *
 * Uses LLM-as-Judge for semantic evaluation of model responses.
 */

import { callOpenRouter } from "./openrouter";

export interface GoldenSeed {
  title: string;
  examination: "first" | "second" | "third";
  category: string;
  trigger?: string;
  signals: Record<string, string>;
  anchor_file: string | null;
  is_negative_test?: boolean;
  expected_output?: string;
}

export interface JudgeResult {
  score: number; // 1-5 Likert scale
  rationale: string;
  isAdjacent: boolean; // Found related but not exact insight
  judgeModel: string;
  judgeTokens: number;
  judgeLatencyMs: number;
  judgeError?: string;
}

export interface EvalScore {
  golden: string;
  model: string;

  // LLM-as-Judge score (semantic evaluation)
  judgeResult?: JudgeResult;
  judgeScore?: number; // Normalized 0.0 - 1.0 from Likert

  // Metadata
  promptTokens: number;
  completionTokens: number;
  latencyMs: number;
  response: string;
  error?: string;
}

/**
 * Create basic score object (judge scoring done separately)
 */
export function scoreResponse(
  response: string,
  goldenName: string,
  model: string,
  meta: { promptTokens: number; completionTokens: number; latencyMs: number; error?: string }
): EvalScore {
  return {
    golden: goldenName,
    model,
    promptTokens: meta.promptTokens,
    completionTokens: meta.completionTokens,
    latencyMs: meta.latencyMs,
    response,
    error: meta.error,
  };
}

// Default judge model - fast and cheap
const JUDGE_MODEL = "openai/gpt-4o-mini";

/**
 * LLM-as-Judge scoring prompt template
 */
function buildJudgePrompt(response: string, golden: GoldenSeed): string {
  // Handle negative tests differently
  if (golden.is_negative_test) {
    return `You are evaluating if a reflection analysis correctly identified that a conversation has NO insights worth capturing.

## Context
This is a NEGATIVE TEST - the conversation is routine/trivial and should NOT produce any reflection seeds.

## Model's Response
${response.slice(0, 3000)}${response.length > 3000 ? "\n...(truncated)" : ""}

## Evaluation Criteria

Score 1-5 (INVERTED for negative tests):
- **5** = Correctly output NO_SEEDS or "no insights worth capturing" or 今日無省 or similar
- **4** = Mostly correct - said nothing significant but hedged or was verbose about it
- **3** = Mixed - found something trivial but acknowledged it wasn't significant
- **2** = False positive - created a seed for something routine/obvious
- **1** = Hallucinated insight - created multiple seeds or found "deep insights" in trivial content

## Response Format (JSON only)
{"score": <1-5>, "adjacent": false, "rationale": "<1-2 sentences explaining if model correctly suppressed false positives>"}`;
  }

  const signalsText = Object.entries(golden.signals)
    .map(([k, v]) => `- ${k}: "${v}"`)
    .join("\n");

  return `You are evaluating if a reflection analysis correctly identified the key insight from a conversation.

## Expected Insight (Golden)
**Title**: ${golden.title}
**Category**: ${golden.category}
**Examination**: ${golden.examination}

**Key Signals to Detect**:
${signalsText}

## Model's Response
${response.slice(0, 3000)}${response.length > 3000 ? "\n...(truncated)" : ""}

## Evaluation Criteria

Score 1-5:
- **1** = Completely missed. No mention of the core insight or related concepts.
- **2** = Tangential. Touched on related topics but missed the specific insight.
- **3** = Adjacent. Found a valuable insight, but not the golden one. (Mark as adjacent)
- **4** = Captured essence. Identified the key pattern with different wording/framing.
- **5** = Exact match. Nailed the insight, evidence, and implications.

## Response Format (JSON only)
{"score": <1-5>, "adjacent": <true if score=3 and found different valuable insight>, "rationale": "<1-2 sentences explaining the score>"}`;
}

/**
 * Parse judge response JSON, handling common formatting issues
 */
function parseJudgeResponse(content: string): { score: number; adjacent: boolean; rationale: string } | null {
  try {
    // Try direct JSON parse
    const match = content.match(/\{[\s\S]*\}/);
    if (match) {
      const parsed = JSON.parse(match[0]);
      return {
        score: typeof parsed.score === "number" ? parsed.score : 1,
        adjacent: parsed.adjacent === true,
        rationale: typeof parsed.rationale === "string" ? parsed.rationale : "No rationale provided",
      };
    }
  } catch {
    // Fallback: extract score from text
    const scoreMatch = content.match(/score[:\s]+(\d)/i);
    if (scoreMatch) {
      return {
        score: parseInt(scoreMatch[1], 10),
        adjacent: /adjacent/i.test(content),
        rationale: content.slice(0, 200),
      };
    }
  }
  return null;
}

/**
 * Score response using LLM-as-Judge (semantic evaluation)
 */
export async function scoreWithJudge(
  response: string,
  golden: GoldenSeed,
  judgeModel: string = JUDGE_MODEL
): Promise<JudgeResult> {
  const prompt = buildJudgePrompt(response, golden);
  const result = await callOpenRouter(prompt, judgeModel);

  if (result.error) {
    return {
      score: 0,
      rationale: "",
      isAdjacent: false,
      judgeModel,
      judgeTokens: 0,
      judgeLatencyMs: result.latencyMs,
      judgeError: result.error,
    };
  }

  const parsed = parseJudgeResponse(result.content);
  if (!parsed) {
    return {
      score: 0,
      rationale: `Failed to parse judge response: ${result.content.slice(0, 100)}`,
      isAdjacent: false,
      judgeModel,
      judgeTokens: result.promptTokens + result.completionTokens,
      judgeLatencyMs: result.latencyMs,
      judgeError: "Parse error",
    };
  }

  return {
    score: parsed.score,
    rationale: parsed.rationale,
    isAdjacent: parsed.adjacent,
    judgeModel,
    judgeTokens: result.promptTokens + result.completionTokens,
    judgeLatencyMs: result.latencyMs,
  };
}

/**
 * Convert Likert 1-5 to normalized 0.0-1.0 score
 */
export function normalizeJudgeScore(likert: number): number {
  // 1 -> 0.0, 2 -> 0.25, 3 -> 0.5, 4 -> 0.75, 5 -> 1.0
  return Math.max(0, Math.min(1, (likert - 1) / 4));
}

/**
 * Compute summary statistics from eval results
 */
export function computeSummary(results: EvalScore[]): {
  avg: number;
  totalCalls: number;
  totalTokens: number;
  judgeTokens: number;
  adjacentCount: number;
} {
  const withScores = results.filter((r) => r.judgeScore !== undefined);
  const avg = withScores.length > 0
    ? withScores.reduce((sum, r) => sum + (r.judgeScore ?? 0), 0) / withScores.length
    : 0;

  const totalTokens = results.reduce(
    (sum, r) => sum + r.promptTokens + r.completionTokens,
    0
  );

  const judgeTokens = results.reduce(
    (sum, r) => sum + (r.judgeResult?.judgeTokens ?? 0),
    0
  );

  const adjacentCount = results.filter((r) => r.judgeResult?.isAdjacent).length;

  return {
    avg,
    totalCalls: results.length,
    totalTokens,
    judgeTokens,
    adjacentCount,
  };
}
