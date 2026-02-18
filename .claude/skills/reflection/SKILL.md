---
name: reflection
description: "Create reflection seeds when you notice opportunities in engineering (security, architecture, complexity), product (UX, features), or meta-patterns (workflow, self-improvement). Seeds get expanded later into actionable improvements."
---

> 吾日三省吾身 — Examine yourself thrice daily.

---

## Quick Decision Tree

```
/reflection invoked
    │
    ├─ Nothing stirring? ──────────────────────► 今日無省 (exit gracefully)
    │
    └─ Something stirring ─────────────────────► Reflect (Step 2A):
                                                    │
                                                    ├─ <thinking>: Generate seedlings (mid-task: 1, pause: 3)
                                                    ├─ Discard weak ones
                                                    ├─ None survive? → 今日無省
                                                    └─ Survivor? → Present to user
                                                          │
                                                          ├─ User: "Create seed" → Write rationale
                                                          ├─ User: "Fix now" → Address immediately
                                                          └─ User: "今日無省" → Exit gracefully
```

**Good rationale = what you noticed + why it matters + what artifact to produce.**

Nothing survives discernment → 今日無省. That's clarity, not failure.

---

## Step 1: Assess

When `/reflection` is invoked, assess your state:

| State | Action |
|-------|--------|
| **Wrapping up / natural pause** | Full reflection (Step 2A, 3 seedlings) |
| **Mid-task** | Fast reflection (Step 2A, 1 seedling) |
| **Nothing stirring** | 今日無省 (Step 2B) |
| **Uncertain** | Ask user |

> 知止 (zhī zhǐ) — Knowing when to stop is not failure. It is clarity.

**If uncertain**, ask:

```
How should I handle reflection right now?
```

Options:
- **Full** - Pause and engage fully
- **Fast** - 30-second filter, then continue
- **今日無省** - Nothing stirring, clarity achieved

---

## Dark Matter

**Dark matter** = context that's present in your session but practically lost in any handoff: failed attempts, error messages, hesitations, rejected approaches, corrections. It's not hidden state — it's context that carries disproportionate weight because you experienced it, and would be flattened in any summary or delegation.

Reflect from what you experienced, not what you'd read in a transcript.

---

## Step 2A: Reflect

You have full session context including tool results, your reasoning, and recent corrections.

### Before Creating ANY Seed

**Step A: Internal Discernment (擇善固執)**

Use a thinking block to generate and filter seedlings. This keeps the deliberation invisible to the user.

**Fast path (mid-task)**: generate only Seedling 1. **Full path (pause)**: generate 3.

```
<thinking>
Seedling 1: [observation]
  → Rooted in dark matter I felt? [yes/no]

Seedling 2 (optional): [observation]
  → Rooted in dark matter I felt? [yes/no]

Seedling 3 (optional): [observation]
  → Rooted in dark matter I felt? [yes/no]

Discard: [which and why]
Seed: [which seedling ripened, or "none"]
</thinking>
```

Discard seedlings that:
- Merely restate what is already known
- Describe a bug that was just fixed
- Cannot trace a path to meaningful change
- Are not rooted in dark matter (hesitations, failures, corrections you experienced)

If no seedling ripens into a seed: proceed to Step 2B (今日無省). This is not failure.

**Step B: Present the seed**

Use AskUserQuestion with the single strongest observation:

```
I observed: [1-2 sentence observation]
This maps to [First/Second/Third] Examination.
```

Options:
- **Create seed** - Capture for later expansion
- **Fix now** - I'll address this immediately
- **今日無省** - Nothing worth capturing (clarity achieved)

### Three Examinations

**First (一省): Engineering Excellence**
> "Am I building this correctly?"

Architecture, security, complexity, patterns, performance.

*Pre-mortem frame*: Assume it's 6 months later and this component has failed.
- **Anchor to dark matter**: Where did you hesitate? Where did the tool lag? Where did you almost make a different choice? Start there.
- What broke? (Be specific: memory? concurrency? coupling? data shape?)
- Trace the path from *existing lines* to that failure.
- If you cannot trace a credible path → 杞人憂天 (worrying the sky will fall). Release it.

**Second (二省): Product & UX**
> "Am I building the right thing?"

UX, features, workflows, user mental models.
- Who would hate this and why?
- What's the user actually trying to accomplish?

**Third (三省): Meta-Cognition**
> "How am I working? What am I learning?"

Process, learnable conventions, tool/hook opportunities.
- Will I encounter this again?
- How can I encode this lesson?

### Dark Matter Signals (You Felt These)

Leverage what you experienced, not just what was said:
- Tool failed multiple times before succeeding
- You considered alternative approaches but rejected them
- User corrected your direction mid-task
- Something took longer than it "should have"
- You made an assumption that almost broke things
- User's tone shifted (frustration, confusion, relief)

### Creating Seeds

```bash
bun ~/.claude/reflections/reflection-state.ts write \
  "<TITLE>" \
  "<RATIONALE>" \
  "<FILE_PATH>" \
  "<START_ANCHOR>" \
  "<END_ANCHOR>"
```

**Title**: Lead with category ("Type safety: ...", "UX: ...", "Meta: ...")

**Rationale**: What you noticed, why it matters, what artifact this should produce.

The artifact goal is concrete: "update SKILL.md with X", "create eslint rule for Y", "add validation to Z". If you can't name the artifact, the observation isn't ripe yet — release it or let it mature.

### Example Seeds (actually expanded, with conclusions)

**一省 (Engineering) — TypeScript pattern extracted from debugging:**
```
Seed: "Extract SDK types via indexed access instead of duplicating"
Signal: ToolExecutionState duplicated as string union in 3 files
Conclusion: "Use type T = SDKType['field'] to extract - changes propagate
  automatically. Check SDK exports before defining types that model SDK structures."
```

**三省 (Meta) — Multi-feature commit workflow gap:**
```
Seed: "Commit skill triage mode for multi-feature changes"
Signal: User provided 3 changelogs mapping to different file sets, we chunked 27→5 commits
Conclusion: "Add triage mode using pr-triage patterns: detection heuristics +
  AskUserQuestion for grouping + sequential multi-commit + prov integration."
```

**三省 (Meta) — Decision framework emerged from PR review session:**
```
Seed: "PR review triage - critical evaluation framework for code review feedback"
Signal: Processed ~15 review items across two rounds. Clear decision framework emerged.

The Anti-Pattern: Blindly accepting all review comments as valid. Reviewers
pattern-match to general best practices without considering specific context.

The Framework That Emerged:
1. Verify the premise - Does reviewer's assumption hold? Example: 'pagination
   cursor may skip messages' assumed batch inserts, but messages created
   sequentially (microsecond timestamps, zero collision probability).
2. Check if already addressed - Several items were duplicates of round 1 fixes.
3. Distinguish context-correct vs generally-correct - API routes using
   new Response() vs remote functions using error() is correct architectural
   separation (REST vs RPC), not inconsistency.
4. Evaluate cost/benefit - MutationObserver for parallax adds ~20 lines for
   non-problem (existing null guards handle it).
5. Accept valid improvements - DRY violations, magic numbers, semantic naming
   (RAF vs setTimeout) were genuinely valuable.

Conclusion: Create pr-triage skill with 5-filter decision framework.
```

**What makes these expandable (vs bad seeds):**

| Good seed | Bad seed |
|-----------|----------|
| "15 items, clear framework emerged" (pattern found) | "PR reviews are tedious" (complaint) |
| "3 changelogs → 5 commits" (concrete evidence) | "Commits could be better" (vague) |
| "Duplicated in 3 files" (specific smell) | "Code could be cleaner" (no anchor) |
| Conclusion creates a skill/changes a doc | Conclusion is "be more careful" |

---

## Step 2B: 今日無省 (Nothing to Examine)

When no observation survives discernment, or when the session state is clear:

```
今日無省 — Today, no examination.
```

This is not failure. This is 澄明 (chéng míng) — clarity.

The absence of a reflection IS the reflection:
- The system is sound
- The path is clear
- The work continues

**Do not fabricate insight to fill silence.** Reflection that merely performs reflection pollutes the seed store with noise. 無為 (wú wéi) — non-action is the action.

---

## Filtering Guidelines

### Seeds Are For
- Meta-cognitive insights ABOUT the work
- Patterns noticed across multiple tasks
- Lessons to encode (skills, hooks, CLAUDE.md)
- Strategic questions needing deeper analysis

### Seeds Are NOT For
- Tactical next-steps (use todos)
- Rephrasing existing tickets
- Implementation plans for known work
- Trivial style preferences
- Every small decision

### Strategic vs Tactical

**❌ Tactical** (skip): "Payment field needs validation"
**✅ Strategic** (create): "User pointed out missing validation twice - pattern worth encoding"

**Test**: Would an expert say "interesting dilemma"? Create it. Would they say "just fix that"? Skip it.

### Auto-Reject Checklist

Do NOT create seed if ANY is true:

- [ ] Describes a bug you just fixed (tactical, not strategic)
- [ ] About syntax errors, typos, or obvious mistakes
- [ ] Uses vague urgency ("crucial", "important") without file anchor
- [ ] User explicitly said "ignore" or "skip"
- [ ] Restates what's already in a commit message this session
- [ ] Speculates about tool behavior not witnessed in this session

---

## Recognizing Reflection-Worthy Moments

Look for **state transitions** where the session trajectory changed:

**1. Assumption Mismatch**
Claude assumed X, but user revealed Y was true.
- User has to re-explain constraints or environment
- User corrects Claude's mental model, not just code

**2. User Intervention**
User stops/redirects Claude mid-task.
- Rejects tool use or plan
- Says "stop", "wait", "too many", "not what I meant"
- Signals: misalignment between Claude's approach and user's actual need

**3. Persistence Wins**
Claude hedged impossibility, but it worked anyway.
- "can't", "won't work", "not readable" → then succeeded
- Theoretical knowledge conflicted with empirical reality

**4. Dead End → Pivot**
Standard approach failed 2+ times, forcing creative solution.
- Tried conventional fix, didn't work
- Found non-obvious workaround error message didn't indicate

**5. Repeated Steering**
User keeps correcting direction (not just typos).
- Multiple "no", "not that", "try X instead"
- Signals: Claude missing user's intent or constraints

---

## Quick Reference

| If ticket exists | → Work from ticket, don't seed |
| If obvious fix | → Just fix it, don't seed |
| If pattern emerges | → Seed it |
| If nothing survives | → 今日無省 (clarity) |
| If uncertain | → Ask user |
