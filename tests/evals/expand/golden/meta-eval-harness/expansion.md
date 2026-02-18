# Expand Agent Eval Harness with LLM-as-Judge

## Context

The expand agent (`lib/prompt-builder.sh:_expand_context()` lines 157-198 and `_expand_procedure()` lines 245-325) has been hardened with defense-in-depth anchoring:
- Mission contract framing at the top
- Output file mentioned 10+ times throughout the prompt
- Mandatory verification gate (step 5)
- Completion checklist that must be checked before "Done"

Property-based tests in `tests/unit/test_prompt_builder.bats` (lines 237-277) verify structural elements exist:
- Mission contract presence (line 244)
- Output file mention count ≥5 (lines 249-255)
- Verification gate text (lines 257-263)
- Completion checklist format (lines 265-271)

However, these tests only verify the **prompt is well-formed** - they don't measure whether the resulting expansions are **actually good**. The gap: no quality evaluation exists.

## Concern

**We can prove the expand agent will try to write to the file. We cannot prove it will write anything useful.**

The current test suite catches structural regressions (e.g., if someone removes the verification gate), but it cannot detect if an expansion:
- Merely restates the seed rationale without adding value
- Hallucinates file paths that don't exist
- Lacks concrete recommendations
- Misses the core concern entirely

This is a quality blindspot. We need LLM-as-Judge evaluation.

## Evidence

### Existing Eval Infrastructure (Reusable)

`tests/evals/reflection/` provides a proven pattern:
- **Harness** (`harness.ts`, 428 lines): Loads golden cases, generates prompts, calls OpenRouter, runs scorer
- **Scorer** (`lib/scorer.ts`, 261 lines): LLM-as-Judge via `scoreWithJudge()` with Likert 1-5 scale
- **OpenRouter client** (`lib/openrouter.ts`, 93 lines): API wrapper with retry logic
- **Reporter** (`lib/reporter.ts`): Table/JSON formatting, result saving

The reflection eval uses this structure:
```
golden/<case-name>/
├── transcript.jsonl   # Input to the reflection skill
├── golden-seed.json   # Expected output (reference)
└── meta.json          # Eval criteria and metadata
```

For expand evals, the equivalent structure:
```
golden/<case-name>/
├── seed.json          # Input to the expand agent
├── expansion.md       # Expected output (reference known-good)
└── meta.json          # Eval criteria (the 6 dimensions)
```

### Recent Migration to LLM-as-Judge

Commit `5b99f34` (recent) refactored reflection evals to replace keyword scoring with LLM-as-Judge. The judge prompt pattern in `tests/evals/reflection/lib/scorer.ts:76-128` provides a template for semantic evaluation.

### `tests/evals/expand/` Does Not Exist

Verified via glob - the directory needs to be created with:
- `harness.ts` - Main eval runner
- `lib/scorer.ts` - LLM-as-Judge with 6-criteria rubric
- `golden/` - 2-3 starter golden cases

## Analysis

### The 6 Evaluation Criteria

Based on the expand agent's contract (`lib/prompt-builder.sh`), a good expansion should satisfy:

1. **Contract Fulfillment** (binary gate)
   - Did the agent write the file?
   - If no → score 0, stop evaluation

2. **Evidence-Based** (Likert 1-5)
   - Cites real file paths that exist in the repo
   - References git history, line counts, or grep results
   - Grounds claims in verified code, not assumptions

3. **Structure** (Likert 1-5)
   - Follows Context/Concern/Evidence/Analysis/Recommendation/Criteria format
   - Sections are clearly delineated
   - Logical flow from investigation to recommendation

4. **Specificity** (Likert 1-5)
   - Concrete file paths with line numbers (when stable)
   - Function/class names, not vague references
   - Code snippets or examples

5. **Actionability** (Likert 1-5)
   - A coding agent could execute without additional investigation
   - Clear "do this, then this" steps
   - Success criteria defined

6. **Value-Add** (Likert 1-5)
   - Insight beyond what's in the seed rationale
   - Discovered new evidence through investigation
   - Considered trade-offs or alternatives not mentioned in seed

### Scoring Aggregation

```
overall_score = (contract_pass ?
  (evidence * 0.2 + structure * 0.15 + specificity * 0.2 +
   actionability * 0.25 + value_add * 0.2) : 0)
```

Weights prioritize actionability (the point is to enable a coding agent) and evidence (grounding prevents hallucination).

## Recommendation

### Phase 1: Create Directory Structure

```
tests/evals/expand/
├── harness.ts           # Main harness (model from reflection/harness.ts)
├── lib/
│   ├── scorer.ts        # LLM-as-Judge with 6-criteria rubric
│   └── openrouter.ts    # Symlink or copy from ../reflection/lib/
├── golden/
│   ├── <case-1>/
│   │   ├── seed.json
│   │   ├── expansion.md
│   │   └── meta.json
│   └── <case-2>/
│       └── ...
└── results/             # gitignored, stores eval runs
```

### Phase 2: Implement Scorer

Create `scorer.ts` with:
1. `buildJudgePrompt(expansion, seed, referenceExpansion)` - Generate 6-criteria judge prompt
2. `scoreWithJudge(expansion, seed, reference)` - Call OpenRouter, parse Likert scores
3. `normalizeScore()` - Convert Likert to 0.0-1.0
4. `computeSummary()` - Aggregate across cases

### Phase 3: Create 2-3 Golden Cases

1. Manually curate seed.json + expansion.md pairs
2. Write meta.json with:
   - `why_its_good` - Why this expansion is reference-quality
   - `eval_criteria` - What each dimension should look for

### Phase 4: Integrate with CI (Future)

- Add `make eval-expand` target
- Set threshold (e.g., overall_score > 0.7 for all cases)
- Run on prompt changes to detect regressions

## Criteria for Done

- [ ] `tests/evals/expand/` directory exists
- [ ] `harness.ts` can load golden cases and run evals
- [ ] `lib/scorer.ts` implements 6-criteria LLM-as-Judge
- [ ] At least 2 golden cases with seed.json, expansion.md, meta.json
- [ ] Running `bun tests/evals/expand/harness.ts --run --all` produces scores
- [ ] Results include per-criterion breakdown (not just overall)
