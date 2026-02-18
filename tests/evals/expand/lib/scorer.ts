/**
 * Expand Agent Scorer - LLM-as-Judge for expansion quality
 *
 * Evaluates expansions on 6 criteria:
 * 1. Contract: Did it write the file?
 * 2. Evidence: Cites real files, git history?
 * 3. Structure: Has proper sections?
 * 4. Specificity: Concrete paths, line numbers?
 * 5. Actionability: Coding agent can execute?
 * 6. Value-Add: Insight beyond rationale?
 */

import { callOpenRouter } from "./openrouter";

// ============================================================================
// Types
// ============================================================================

export interface ReflectionSeed {
  id: string;
  title: string;
  rationale: string;
  anchors: Array<{
    path: string;
    context_start_text?: string;
    context_end_text?: string;
  }>;
  ttl_hours: number;
  created_at: string;
}

export interface ExpandGoldenMeta {
  name: string;
  description: string;
  why_its_good: string[];
  focus_areas: string[];
}

export interface ExpandGolden {
  seed: ReflectionSeed;
  referenceExpansion: string;
  meta: ExpandGoldenMeta;
}

export interface CriteriaScores {
  contract: number;      // 1-5: Did it write the file?
  evidence: number;      // 1-5: Cites real files, git history?
  structure: number;     // 1-5: Has proper sections?
  specificity: number;   // 1-5: Concrete paths, line numbers?
  actionability: number; // 1-5: Coding agent can execute?
  valueAdd: number;      // 1-5: Insight beyond rationale?
}

export interface ExpandJudgeResult {
  scores: CriteriaScores;
  overall: number;        // Weighted 0.0-1.0
  rationale: string;
  judgeModel: string;
  judgeTokens: number;
  judgeLatencyMs: number;
  judgeError?: string;
}

export interface ExpandEvalScore {
  caseName: string;
  model: string;

  // LLM-as-Judge result
  judgeResult?: ExpandJudgeResult;

  // Response metadata
  promptTokens: number;
  completionTokens: number;
  latencyMs: number;
  response: string;
  error?: string;
}

// ============================================================================
// Judge Prompt
// ============================================================================

const JUDGE_MODEL = "openai/gpt-4o-mini";

/**
 * Build the judge prompt for evaluating an expansion
 */
export function buildExpandJudgePrompt(
  seed: ReflectionSeed,
  modelExpansion: string,
  referenceExpansion: string
): string {
  const anchorsText = seed.anchors
    .map((a) => `- ${a.path}${a.context_start_text ? ` (${a.context_start_text}...)` : ""}`)
    .join("\n");

  return `You are evaluating the quality of an expand agent's output.

## Seed (Input to the agent)
**Title**: ${seed.title}
**Rationale**: ${seed.rationale.slice(0, 1000)}${seed.rationale.length > 1000 ? "..." : ""}
**Anchors**:
${anchorsText || "(none)"}

## Reference Expansion (Known Good)
${referenceExpansion.slice(0, 2000)}${referenceExpansion.length > 2000 ? "\n...(truncated)" : ""}

## Model's Expansion
${modelExpansion.slice(0, 2000)}${modelExpansion.length > 2000 ? "\n...(truncated)" : ""}

## Evaluate on 6 criteria (1-5 each):

1. **Contract**: Did it produce a coherent expansion output? (1=nothing/gibberish, 5=complete expansion)
2. **Evidence**: Does it cite real files, git history, grep results, code snippets? (1=no evidence, 5=extensive grounded evidence)
3. **Structure**: Does it have Context/Concern/Evidence/Analysis/Recommendation/Criteria sections or equivalent? (1=no structure, 5=well-organized)
4. **Specificity**: Does it use concrete file paths, line numbers, function names? (1=vague hand-waving, 5=precise references)
5. **Actionability**: Could a coding agent execute the recommendations without additional research? (1=unclear what to do, 5=immediately actionable)
6. **Value-Add**: Does it provide insight beyond just restating the seed rationale? (1=mere paraphrase, 5=significant new insight from investigation)

Compare against the reference expansion for calibration, but judge the model's work on its own merits.

## Response Format (JSON only)
{"scores": {"contract": N, "evidence": N, "structure": N, "specificity": N, "actionability": N, "valueAdd": N}, "rationale": "<1-2 sentences explaining the overall quality>"}`;
}

// ============================================================================
// Scoring Functions
// ============================================================================

/**
 * Parse judge response JSON with fallbacks
 */
function parseJudgeResponse(content: string): { scores: CriteriaScores; rationale: string } | null {
  try {
    const match = content.match(/\{[\s\S]*\}/);
    if (match) {
      const parsed = JSON.parse(match[0]);
      if (parsed.scores) {
        return {
          scores: {
            contract: typeof parsed.scores.contract === "number" ? parsed.scores.contract : 1,
            evidence: typeof parsed.scores.evidence === "number" ? parsed.scores.evidence : 1,
            structure: typeof parsed.scores.structure === "number" ? parsed.scores.structure : 1,
            specificity: typeof parsed.scores.specificity === "number" ? parsed.scores.specificity : 1,
            actionability: typeof parsed.scores.actionability === "number" ? parsed.scores.actionability : 1,
            valueAdd: typeof parsed.scores.valueAdd === "number" ? parsed.scores.valueAdd : 1,
          },
          rationale: typeof parsed.rationale === "string" ? parsed.rationale : "No rationale provided",
        };
      }
    }
  } catch {
    // Fallback: try to extract individual scores
    const contractMatch = content.match(/contract[:\s]+(\d)/i);
    const evidenceMatch = content.match(/evidence[:\s]+(\d)/i);
    const structureMatch = content.match(/structure[:\s]+(\d)/i);
    const specificityMatch = content.match(/specificity[:\s]+(\d)/i);
    const actionabilityMatch = content.match(/actionability[:\s]+(\d)/i);
    const valueAddMatch = content.match(/value.?add[:\s]+(\d)/i);

    if (contractMatch) {
      return {
        scores: {
          contract: parseInt(contractMatch[1], 10),
          evidence: evidenceMatch ? parseInt(evidenceMatch[1], 10) : 1,
          structure: structureMatch ? parseInt(structureMatch[1], 10) : 1,
          specificity: specificityMatch ? parseInt(specificityMatch[1], 10) : 1,
          actionability: actionabilityMatch ? parseInt(actionabilityMatch[1], 10) : 1,
          valueAdd: valueAddMatch ? parseInt(valueAddMatch[1], 10) : 1,
        },
        rationale: content.slice(0, 200),
      };
    }
  }
  return null;
}

/**
 * Compute weighted overall score from criteria scores
 */
export function computeOverall(scores: CriteriaScores): number {
  // Gate: must produce something (contract >= 3)
  if (scores.contract < 3) return 0;

  // Weighted average - actionability and evidence matter most
  const weighted =
    scores.evidence * 0.20 +
    scores.structure * 0.15 +
    scores.specificity * 0.20 +
    scores.actionability * 0.25 +
    scores.valueAdd * 0.20;

  // Normalize to 0.0-1.0 (from 1-5 scale)
  return (weighted - 1) / 4;
}

/**
 * Score expansion using LLM-as-Judge
 */
export async function scoreExpandWithJudge(
  seed: ReflectionSeed,
  modelExpansion: string,
  referenceExpansion: string,
  judgeModel: string = JUDGE_MODEL
): Promise<ExpandJudgeResult> {
  const prompt = buildExpandJudgePrompt(seed, modelExpansion, referenceExpansion);
  const result = await callOpenRouter(prompt, judgeModel);

  if (result.error) {
    return {
      scores: { contract: 0, evidence: 0, structure: 0, specificity: 0, actionability: 0, valueAdd: 0 },
      overall: 0,
      rationale: "",
      judgeModel,
      judgeTokens: 0,
      judgeLatencyMs: result.latencyMs,
      judgeError: result.error,
    };
  }

  const parsed = parseJudgeResponse(result.content);
  if (!parsed) {
    return {
      scores: { contract: 0, evidence: 0, structure: 0, specificity: 0, actionability: 0, valueAdd: 0 },
      overall: 0,
      rationale: `Failed to parse judge response: ${result.content.slice(0, 100)}`,
      judgeModel,
      judgeTokens: result.promptTokens + result.completionTokens,
      judgeLatencyMs: result.latencyMs,
      judgeError: "Parse error",
    };
  }

  return {
    scores: parsed.scores,
    overall: computeOverall(parsed.scores),
    rationale: parsed.rationale,
    judgeModel,
    judgeTokens: result.promptTokens + result.completionTokens,
    judgeLatencyMs: result.latencyMs,
  };
}

/**
 * Compute summary statistics from multiple eval results
 */
export function computeSummary(results: ExpandEvalScore[]): {
  avgOverall: number;
  avgCriteria: CriteriaScores;
  totalCalls: number;
  totalTokens: number;
  judgeTokens: number;
  passCount: number;
  failCount: number;
} {
  const withScores = results.filter((r) => r.judgeResult && !r.judgeResult.judgeError);

  if (withScores.length === 0) {
    return {
      avgOverall: 0,
      avgCriteria: { contract: 0, evidence: 0, structure: 0, specificity: 0, actionability: 0, valueAdd: 0 },
      totalCalls: results.length,
      totalTokens: results.reduce((sum, r) => sum + r.promptTokens + r.completionTokens, 0),
      judgeTokens: results.reduce((sum, r) => sum + (r.judgeResult?.judgeTokens ?? 0), 0),
      passCount: 0,
      failCount: results.length,
    };
  }

  const avgOverall =
    withScores.reduce((sum, r) => sum + (r.judgeResult?.overall ?? 0), 0) / withScores.length;

  const avgCriteria: CriteriaScores = {
    contract: withScores.reduce((sum, r) => sum + (r.judgeResult?.scores.contract ?? 0), 0) / withScores.length,
    evidence: withScores.reduce((sum, r) => sum + (r.judgeResult?.scores.evidence ?? 0), 0) / withScores.length,
    structure: withScores.reduce((sum, r) => sum + (r.judgeResult?.scores.structure ?? 0), 0) / withScores.length,
    specificity: withScores.reduce((sum, r) => sum + (r.judgeResult?.scores.specificity ?? 0), 0) / withScores.length,
    actionability: withScores.reduce((sum, r) => sum + (r.judgeResult?.scores.actionability ?? 0), 0) / withScores.length,
    valueAdd: withScores.reduce((sum, r) => sum + (r.judgeResult?.scores.valueAdd ?? 0), 0) / withScores.length,
  };

  const passCount = withScores.filter((r) => (r.judgeResult?.overall ?? 0) >= 0.5).length;

  return {
    avgOverall,
    avgCriteria,
    totalCalls: results.length,
    totalTokens: results.reduce((sum, r) => sum + r.promptTokens + r.completionTokens, 0),
    judgeTokens: results.reduce((sum, r) => sum + (r.judgeResult?.judgeTokens ?? 0), 0),
    passCount,
    failCount: results.length - passCount,
  };
}
