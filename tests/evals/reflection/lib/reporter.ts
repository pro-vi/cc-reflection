/**
 * Output formatting for reflection evals
 */

import type { EvalScore } from "./scorer";

export interface EvalReport {
  timestamp: string;
  model: string;
  results: EvalScore[];
  summary: {
    avg: number;
    totalCalls: number;
    totalTokens: number;
    judgeTokens: number;
    adjacentCount: number;
  };
}

/**
 * Format results as ASCII table
 */
export function formatTable(results: EvalScore[], summary: EvalReport["summary"]): string {
  const lines: string[] = [];

  // Header
  lines.push("┌" + "─".repeat(28) + "┬" + "─".repeat(9) + "┬" + "─".repeat(40) + "┐");
  lines.push(
    "│ " + "Golden".padEnd(26) + " │ " + "Judge".padEnd(7) + " │ " + "Rationale".padEnd(38) + " │"
  );
  lines.push("├" + "─".repeat(28) + "┼" + "─".repeat(9) + "┼" + "─".repeat(40) + "┤");

  // Rows
  for (const r of results) {
    const golden = r.golden.slice(0, 26).padEnd(26);
    const judgeScore = r.judgeScore !== undefined ? `${r.judgeResult?.score}/5` : "n/a";
    const judgeStatus = r.judgeResult?.isAdjacent ? "adj" : (r.judgeResult?.score ?? 0) >= 4 ? "✓" : (r.judgeResult?.score ?? 0) >= 3 ? "~" : "⚠️";
    const judgeCol = `${judgeScore} ${judgeStatus}`.padEnd(7);
    const rationale = (r.judgeResult?.rationale ?? "").slice(0, 38).padEnd(38);
    lines.push(`│ ${golden} │ ${judgeCol} │ ${rationale} │`);
  }

  lines.push("└" + "─".repeat(28) + "┴" + "─".repeat(9) + "┴" + "─".repeat(40) + "┘");

  // Summary
  lines.push("");
  lines.push("Summary:");
  lines.push(`  Judge avg:        ${(summary.avg * 100).toFixed(1)}%`);
  if (summary.adjacentCount > 0) {
    lines.push(`  Adjacent:         ${summary.adjacentCount}`);
  }
  lines.push("");
  lines.push(`  API calls:        ${summary.totalCalls}`);
  lines.push(`  Eval tokens:      ${summary.totalTokens}`);
  lines.push(`  Judge tokens:     ${summary.judgeTokens}`);

  return lines.join("\n");
}

/**
 * Format results as JSON
 */
export function formatJson(report: EvalReport): string {
  // Strip full response from JSON output to keep it manageable
  const sanitized = {
    ...report,
    results: report.results.map((r) => ({
      ...r,
      response: r.response.slice(0, 500) + (r.response.length > 500 ? "..." : ""),
    })),
  };
  return JSON.stringify(sanitized, null, 2);
}

/**
 * Print single result details (verbose mode)
 */
export function formatVerbose(result: EvalScore): string {
  const lines: string[] = [];

  lines.push(`\n--- ${result.golden} ---`);
  lines.push(`Model: ${result.model}`);

  // Judge results
  if (result.judgeResult) {
    const jr = result.judgeResult;
    lines.push(`Judge: ${jr.score}/5 (${result.judgeScore?.toFixed(2) ?? "n/a"})${jr.isAdjacent ? " [ADJACENT]" : ""}`);
    lines.push(`Rationale: ${jr.rationale}`);
    if (jr.judgeError) {
      lines.push(`Judge error: ${jr.judgeError}`);
    }
  }

  lines.push(`Latency: ${result.latencyMs}ms | Tokens: ${result.promptTokens}+${result.completionTokens}`);

  if (result.error) {
    lines.push(`Error: ${result.error}`);
  }

  lines.push(`\nResponse preview:\n${result.response.slice(0, 800)}${result.response.length > 800 ? "..." : ""}`);

  return lines.join("\n");
}

/**
 * Save report to results directory
 */
export async function saveReport(report: EvalReport, resultsDir: string): Promise<string> {
  const date = new Date().toISOString().split("T")[0];
  const modelSlug = report.model.replace(/\//g, "-");
  const filename = `${date}-${modelSlug}.json`;
  const filepath = `${resultsDir}/${filename}`;

  await Bun.write(filepath, formatJson(report));
  return filepath;
}
