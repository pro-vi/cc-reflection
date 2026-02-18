# Research Agents Skill for Fract.ai

## Purpose

Investigate patterns across 8 open-source coding agent repositories with **domain translation awareness**. These repos operate on FILES with paths; Fract.ai operates on BLOCKS with UUIDs. Direct pattern adoption fails when assumptions don't transfer.

---

## Execution Instructions

When the user invokes this skill with a research question (e.g., "Research how agents handle stale file detection"):

### Step 1: Spawn 8 Parallel Explore Agents

Use the Task tool with `subagent_type: "Explore"` for each repository:

```
~/Development/_research/coding-agents/aider
~/Development/_research/coding-agents/cline
~/Development/_research/coding-agents/continue
~/Development/_research/coding-agents/openhands
~/Development/_research/coding-agents/open-interpreter
~/Development/_research/coding-agents/swe-agent
~/Development/_research/coding-agents/taskweaver
~/Development/_research/coding-agents/opendevin
```

**Inject this context into EACH agent prompt:**

```markdown
## Domain Translation Context

You are exploring a CODING AGENT that operates on FILES with human-readable paths.
The findings will be adapted to FRACT.AI, a DOCUMENT AGENT that operates on BLOCKS with UUIDs.

### Critical Translation Table

| Coding Agent Concept | Fract.ai Equivalent | Why It Matters |
|----------------------|---------------------|----------------|
| File path | Block position in document | Paths are hierarchical/human-readable; UUIDs are flat/random |
| Filename | Block ID (machine-generated) | Users never type block IDs |
| Directory structure | Space hierarchy (parent/child) | Spatial grouping differs |
| File extension (.ts, .py) | Block type (paragraph, code, list) | Type identification mechanism |
| Line number | Intra-block offset | Granularity of position |
| git diff / mtime | Content hash + version | State tracking mechanism |
| Repository | Space | Container concept |

### When You Find a Pattern, Flag These:

1. **ASSUMPTION CHECK**: Does this pattern assume human-readable identifiers? (paths, filenames)
2. **SIMILARITY METRIC**: What makes items "similar"? (prefix? directory? content?)
3. **USER INPUT**: Does it expect users to type partial identifiers?
4. **TRANSLATION**: What's the Fract.ai equivalent? Use the table above.

Mark patterns with:
- 🟢 TRANSFERS DIRECTLY — mechanism works as-is
- 🟡 NEEDS ADAPTATION — mechanism valid, but similarity/identity logic must change
- 🔴 DOESN'T TRANSFER — relies on file-path semantics we don't have
```

### Step 2: Synthesize Findings

After all 8 agents return, create:

#### A. Comparison Table

| Repository | Pattern Found | File:Line | Transfers? | Adaptation Needed |
|------------|---------------|-----------|------------|-------------------|
| aider | ... | ... | 🟡 | ... |
| cline | ... | ... | 🟢 | ... |
| ... | ... | ... | ... | ... |

#### B. Pattern Adaptation Checklist (per finding)

For EACH pattern discovered:

```markdown
### Pattern: [Name from source]
**Source:** [repo] — [file:line]

#### Assumptions (verify each)
- [ ] Items have meaningful prefixes → ❌/✅ (UUIDs don't)
- [ ] Users type partial identifiers → ❌/✅ (agents use full IDs)
- [ ] Similarity based on string matching → ❌/✅ (need position/type/content)
- [ ] [other assumptions discovered]

#### Domain Mapping
| Their Concept | Our Equivalent |
|---------------|----------------|
| ... | ... |

#### Mechanism Transfer
- Core mechanism: [what it does]
- Transfers: ✅/❌
- Adaptation required: [describe]

#### Adapted Implementation Sketch
```typescript
// Their approach
...

// Our adaptation
...
```
```

#### C. Recommendation

Synthesize the best pattern(s) with explicit assumption verification completed.

---

## Example Execution

**User:** "Research how agents handle error recovery with similar item suggestions"

**Agent spawns 8 explorers with domain context, receives:**

```
AIDER: find_similar_lines() in editblock_coder.py:82 — uses prefix matching on filenames
       🔴 DOESN'T TRANSFER — relies on meaningful prefixes, UUIDs have none

CLINE: FileContextTracker in context-tracking/FileContextTracker.ts:66 — file watcher pattern
       🟡 NEEDS ADAPTATION — mechanism valid, trigger changes to block mutation listener

SWE-AGENT: windowed_file.py:150 — position-based navigation with overlap
       🟢 TRANSFERS DIRECTLY — block index = line number equivalent
```

**Synthesis:**
- Aider's prefix matching: mechanism good, similarity metric must change to position+type
- Cline's file watcher: adapt to Lexical update listener
- SWE-Agent's windowing: directly applicable to block navigation

---

## Origin: Pattern Adaptation Protocol

This skill operationalizes the lesson from FRAC-46 where we incorrectly adopted Aider's did-you-mean pattern with UUID prefix matching (useless) before pivoting to position+type-based similarity.

**The 5-Step Protocol (embedded in agent prompts above):**
1. Identify core assumptions
2. Map domain concepts
3. Verify mechanism transfers
4. Design adapted implementation
5. Document the translation

---

## Files Reference

- Existing research: `docs/research/agent-context-scaffolding-patterns.md`
- Implementation recommendations: `docs/research/harness-implementation-recommendations.md`
- Agent tools: `src/lib/agents/tools.ts`
- CLAUDE.md research template: lines 477-499

---

## Success Criteria

- [ ] All 8 repos explored with domain context injected
- [ ] Each finding has Pattern Adaptation Checklist completed
- [ ] Assumptions explicitly listed and verified (not assumed to transfer)
- [ ] Adapted implementation sketches differ from source when assumptions diverge
- [ ] Final recommendation grounded in Fract.ai's block-based architecture
