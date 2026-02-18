/**
 * Reporter for expand eval results
 *
 * Formats evaluation results as tables or JSON.
 */

import type { ExpandEvalScore, CriteriaScores } from "./scorer";

// ============================================================================
// Types
// ============================================================================

export interface ExpandEvalReport {
  timestamp: string;
  model: string;
  results: ExpandEvalScore[];
  summary: {
    avgOverall: number;
    avgCriteria: CriteriaScores;
    totalCalls: number;
    totalTokens: number;
    judgeTokens: number;
    passCount: number;
    failCount: number;
  };
}

// ============================================================================
// Formatting
// ============================================================================

/**
 * Format criteria scores as compact string
 */
function formatCriteria(scores: CriteriaScores): string {
  return `C:${scores.contract} E:${scores.evidence} S:${scores.structure} Sp:${scores.specificity} A:${scores.actionability} V:${scores.valueAdd}`;
}

/**
 * Format overall score with pass/fail indicator
 */
function formatOverall(overall: number): string {
  const pct = (overall * 100).toFixed(0);
  if (overall >= 0.7) return `${pct}% ✓`;
  if (overall >= 0.5) return `${pct}% ~`;
  if (overall > 0) return `${pct}% ⚠️`;
  return `${pct}% ✗`;
}

/**
 * Format results as ASCII table
 */
export function formatTable(results: ExpandEvalScore[], summary: ExpandEvalReport["summary"]): string {
  const lines: string[] = [];

  // Header
  lines.push("┌────────────────────────┬─────────┬────────────────────────────────┬─────────────────────────────────────────┐");
  lines.push("│ Case                   │ Overall │ Criteria (C E S Sp A V)        │ Rationale                               │");
  lines.push("├────────────────────────┼─────────┼────────────────────────────────┼─────────────────────────────────────────┤");

  // Results
  for (const result of results) {
    const caseName = result.caseName.slice(0, 22).padEnd(22);
    const overall = result.judgeResult
      ? formatOverall(result.judgeResult.overall).padEnd(7)
      : "ERR".padEnd(7);
    const criteria = result.judgeResult
      ? formatCriteria(result.judgeResult.scores).padEnd(30)
      : "N/A".padEnd(30);
    const rationale = result.judgeResult?.rationale?.slice(0, 37).padEnd(37) || result.error?.slice(0, 37).padEnd(37) || "".padEnd(37);

    lines.push(`│ ${caseName} │ ${overall} │ ${criteria} │ ${rationale} │`);
  }

  lines.push("└────────────────────────┴─────────┴────────────────────────────────┴─────────────────────────────────────────┘");

  // Summary
  lines.push("");
  lines.push(`Summary: ${summary.passCount}/${summary.totalCalls} passed (>= 50%)`);
  lines.push(`Average: ${(summary.avgOverall * 100).toFixed(1)}%`);
  lines.push(`Criteria Avg: ${formatCriteria(summary.avgCriteria)}`);
  lines.push(`Tokens: ${summary.totalTokens} model + ${summary.judgeTokens} judge`);

  return lines.join("\n");
}

/**
 * Format single result verbosely
 */
export function formatVerbose(result: ExpandEvalScore): string {
  const lines: string[] = [];

  lines.push(`## ${result.caseName}`);
  lines.push("");

  if (result.error) {
    lines.push(`**Error**: ${result.error}`);
    return lines.join("\n");
  }

  if (result.judgeResult) {
    const jr = result.judgeResult;
    lines.push(`**Overall**: ${formatOverall(jr.overall)}`);
    lines.push("");
    lines.push("**Criteria Scores**:");
    lines.push(`- Contract: ${jr.scores.contract}/5`);
    lines.push(`- Evidence: ${jr.scores.evidence}/5`);
    lines.push(`- Structure: ${jr.scores.structure}/5`);
    lines.push(`- Specificity: ${jr.scores.specificity}/5`);
    lines.push(`- Actionability: ${jr.scores.actionability}/5`);
    lines.push(`- Value-Add: ${jr.scores.valueAdd}/5`);
    lines.push("");
    lines.push(`**Rationale**: ${jr.rationale}`);
    lines.push("");
    lines.push(`**Judge**: ${jr.judgeModel} (${jr.judgeTokens} tokens, ${jr.judgeLatencyMs}ms)`);
  }

  lines.push("");
  lines.push(`**Model Response** (${result.completionTokens} tokens, ${result.latencyMs}ms):`);
  lines.push("```");
  lines.push(result.response.slice(0, 500) + (result.response.length > 500 ? "..." : ""));
  lines.push("```");

  return lines.join("\n");
}

/**
 * Format report as JSON (sanitized for size)
 */
export function formatJson(report: ExpandEvalReport): string {
  const sanitized = {
    ...report,
    results: report.results.map((r) => ({
      ...r,
      response: r.response.slice(0, 500),
    })),
  };
  return JSON.stringify(sanitized, null, 2);
}

/**
 * Save report to results directory
 */
export async function saveReport(report: ExpandEvalReport, resultsDir: string): Promise<string> {
  const date = new Date().toISOString().slice(0, 10);
  const modelSlug = report.model.replace(/[^a-z0-9]/gi, "-").toLowerCase();
  const filename = `${date}-${modelSlug}.json`;
  const filepath = `${resultsDir}/${filename}`;

  await Bun.write(filepath, formatJson(report));
  return filepath;
}
