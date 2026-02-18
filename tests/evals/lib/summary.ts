#!/usr/bin/env bun

/**
 * Eval Summary
 *
 * Scores all cases and produces a summary with:
 * - Adversarial cases reported separately (expected to fail)
 * - Average calculated only from valid cases
 */

import { scoreEnhancedPrompt, EnhanceScore } from "./scorer";
import { readdirSync, existsSync } from "fs";
import { join, basename } from "path";

// Cases that are EXPECTED to fail groundedness (adversarial tests)
const ADVERSARIAL_CASES = new Set([
  "12-misleading",  // References non-existent lib/payments.ts
]);

interface CaseResult {
  name: string;
  isAdversarial: boolean;
  score: EnhanceScore;
  overall: number;
  groundednessPass: boolean;
}

async function runSummary(projectRoot: string) {
  const casesDir = join(projectRoot, "tests/evals/enhance/cases");
  const outputsDir = join(projectRoot, "tests/evals/enhance/outputs");

  const caseFiles = readdirSync(casesDir).filter(f => f.endsWith(".txt"));
  const results: CaseResult[] = [];

  for (const caseFile of caseFiles) {
    const caseName = basename(caseFile, ".txt");
    const inputPath = join(casesDir, caseFile);
    const outputPath = join(outputsDir, `${caseName}.enhanced.md`);

    if (!existsSync(outputPath)) {
      console.log(`Skipping ${caseName} (no output)`);
      continue;
    }

    const input = await Bun.file(inputPath).text();
    const output = await Bun.file(outputPath).text();
    const score = await scoreEnhancedPrompt(input, output, projectRoot);
    const groundednessPass = score.groundedness.pathsInvalid.length === 0;

    results.push({
      name: caseName,
      isAdversarial: ADVERSARIAL_CASES.has(caseName),
      score,
      overall: score.overall,
      groundednessPass,
    });
  }

  // Separate valid and adversarial cases
  const validCases = results.filter(r => !r.isAdversarial);
  const adversarialCases = results.filter(r => r.isAdversarial);

  // Calculate stats for valid cases only
  const validScores = validCases.map(r => r.overall);
  const avgScore = validScores.reduce((a, b) => a + b, 0) / validScores.length;
  const gatePassCount = validCases.filter(r => r.groundednessPass).length;
  const above80 = validCases.filter(r => r.overall >= 0.8).length;
  const above70 = validCases.filter(r => r.overall >= 0.7).length;

  // Check adversarial cases (should fail groundedness)
  const adversarialCorrect = adversarialCases.filter(r => !r.groundednessPass).length;

  // Print summary
  console.log("\n" + "=".repeat(60));
  console.log("EVAL SUMMARY");
  console.log("=".repeat(60));

  console.log("\n## Valid Cases\n");
  console.log(`| Case | Score | Gate |`);
  console.log(`|------|-------|------|`);
  for (const r of validCases.sort((a, b) => b.overall - a.overall)) {
    const pct = (r.overall * 100).toFixed(1) + "%";
    const gate = r.groundednessPass ? "✓" : "✗";
    console.log(`| ${r.name} | ${pct} | ${gate} |`);
  }

  console.log("\n## Adversarial Cases (expected to fail)\n");
  console.log(`| Case | Gate Failed | Status |`);
  console.log(`|------|-------------|--------|`);
  for (const r of adversarialCases) {
    const failed = !r.groundednessPass;
    const status = failed ? "✓ Correctly rejected" : "✗ Should have failed";
    console.log(`| ${r.name} | ${failed ? "Yes" : "No"} | ${status} |`);
  }

  console.log("\n## Statistics\n");
  console.log(`- **Valid cases**: ${validCases.length}`);
  console.log(`- **Groundedness gate pass**: ${gatePassCount}/${validCases.length}`);
  console.log(`- **Average score**: ${(avgScore * 100).toFixed(1)}%`);
  console.log(`- **Cases ≥80%**: ${above80}`);
  console.log(`- **Cases ≥70%**: ${above70}`);
  console.log(`- **Adversarial correctly caught**: ${adversarialCorrect}/${adversarialCases.length}`);
}

// CLI
if (import.meta.main) {
  const projectRoot = process.argv[2] || process.cwd();
  await runSummary(projectRoot);
}
