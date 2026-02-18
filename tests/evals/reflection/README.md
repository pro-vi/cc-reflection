# Reflection Eval

Tests whether models can identify golden seeds from conversation transcripts using the SKILL.md prompt. Uses LLM-as-Judge (GPT-4o-mini) for semantic scoring.

## Setup

```bash
cp .env.example .env  # add OPENROUTER_API_KEY
```

## Usage

```bash
# List available goldens (8 positive + 3 negative)
bun tests/evals/reflection/harness.ts --list

# Preview prompt for manual testing (no API key needed)
bun tests/evals/reflection/harness.ts user-intervention-complexity

# Run single golden
bun tests/evals/reflection/harness.ts --run user-intervention-complexity

# Run all goldens, save results
bun tests/evals/reflection/harness.ts --run --all --save

# Swap model
bun tests/evals/reflection/harness.ts --run --all --model google/gemini-flash-1.5

# Skip judge (faster/cheaper, keyword scoring only)
bun tests/evals/reflection/harness.ts --run --all --no-judge

# Verbose output (full responses + judge rationale)
bun tests/evals/reflection/harness.ts --run --all --verbose

# JSON output
bun tests/evals/reflection/harness.ts --run --all --output json
```

## When to run

- **After editing SKILL.md** -- copy it to `prompts/skill.md`, run `--run --all --save`, compare against previous results
- **After adding new goldens** -- run the new golden individually first, then `--all`

## Structure

```
tests/evals/reflection/
  harness.ts              # CLI entry point
  prompts/
    skill.md              # Current SKILL.md (copy from .claude/skills/reflection/SKILL.md)
  golden/
    <name>/
      transcript.jsonl    # Conversation transcript
      golden-seed.json    # Expected seed (title, examination, signals, anchor)
      meta.json           # Eval criteria and expected detection
  results/                # Saved JSON reports (gitignored)
  lib/
    scorer.ts             # Judge prompt, scoring, summary stats
    reporter.ts           # Table/JSON/verbose formatters
    openrouter.ts         # OpenRouter API client
```

## Goldens

Each golden directory contains a real conversation transcript paired with the seed a good reflection should produce. Negative goldens (`negative-*`) test that the model correctly outputs NO_SEEDS for routine/trivial conversations.

## Scoring

The judge scores on a 1-5 Likert scale:

| Score | Meaning |
|-------|---------|
| 5 | Exact match -- nailed insight, evidence, implications |
| 4 | Captured essence with different wording |
| 3 | Adjacent -- found valuable but different insight |
| 2 | Tangential -- touched related topics, missed the point |
| 1 | Completely missed |

Negative tests use an inverted scale (5 = correctly suppressed, 1 = hallucinated insight).

Scores are normalized to 0.0-1.0 for the summary average.

## Comparing results over time

Results are saved to `results/YYYY-MM-DD-model-name.json`. Compare manually or diff the JSON files across runs to track regression.
