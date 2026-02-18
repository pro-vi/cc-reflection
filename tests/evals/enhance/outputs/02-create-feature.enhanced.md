## Add Seeds Export Command

### CONTEXT (Verified Existing)

**Core Files:**
- `lib/reflection-state.ts` (526 lines) - ReflectionStateManager class with public methods:
  - `listSeeds(filter: MenuFilter): ReflectionSeed[]` - retrieves seeds (line 270)
  - `getSeed(seedId: string): ReflectionSeed | null` - retrieves single seed
  - CLI interface with switch cases handling various operations (lines 729-951)
  - Current operations: write, list, list-all, get, delete, cleanup, archive, unarchive, conclude, etc.
  - **No export functionality currently exists**

- `lib/reflection-state.ts` ReflectionSeed interface (lines 62-76):
  - `id`: string (format: `seed-TIMESTAMP-RANDOM`)
  - `title`: string
  - `rationale`: string
  - `anchors`: ReflectionAnchor[] (path + context text)
  - `ttl_hours`: number
  - `created_at`: ISO string
  - `status`: 'active' | 'archived'
  - `freshness_tier`: '🌱' | '💭' | '💤' | '📦'
  - `expansions`: ExpansionRecord[] (timestamp + conclusion history)

- `Makefile` (233 lines) - Has precedent for list-related commands:
  - `make list-seeds` (line 167-168) - prints seeds to stdout

- `bin/` directory contains specialized commands:
  - `cc-reflect-preview-seed` - displays individual seed details
  - Follows pattern: read session ID → use ReflectionStateManager → format output

### ACTION (What to do)

**Step 1: Add export method to ReflectionStateManager**

Add new CLI case in `lib/reflection-state.ts` after line 951 (end of existing cases):

```typescript
case "export-markdown": {
  const filter = (args[1] || 'active') as MenuFilter

  // Validate filter
  if (!isMenuFilter(filter)) {
    console.error(`Invalid filter: ${filter}`)
    process.exit(1)
  }

  // Get seeds
  const seeds = manager.listSeeds(filter)

  // Generate markdown
  const markdown = generateMarkdownExport(seeds)
  console.log(markdown)
  break
}
```

**Step 2: Add markdown generation helper function**

Add before the switch statement (around line 720):

```typescript
function generateMarkdownExport(seeds: ReflectionSeed[]): string {
  if (seeds.length === 0) {
    return "# Reflection Seeds\n\nNo seeds found.\n"
  }

  let md = "# Reflection Seeds\n\n"
  md += `Generated: ${new Date().toISOString()}\n`
  md += `Total: ${seeds.length} seeds\n\n`

  for (const seed of seeds) {
    md += `## ${seed.title}\n\n`
    md += `- **ID**: \`${seed.id}\`\n`
    md += `- **Status**: ${seed.status || 'active'} ${seed.freshness_tier || '💭'}\n`
    md += `- **Created**: ${new Date(seed.created_at).toLocaleString()}\n`
    md += `- **Expires in**: ${seed.ttl_hours} hours\n`

    if (seed.rationale) {
      md += `\n**Rationale**:\n${seed.rationale}\n`
    }

    if (seed.anchors && seed.anchors.length > 0) {
      md += "\n**Context**:\n"
      for (const anchor of seed.anchors) {
        md += `- \`${anchor.path}\`: ${anchor.context_start_text.substring(0, 60)}...\n`
      }
    }

    if (seed.expansions && seed.expansions.length > 0) {
      md += "\n**Expansion History**:\n"
      for (const exp of seed.expansions) {
        md += `- **${new Date(exp.timestamp).toLocaleDateString()}**: ${exp.conclusion.substring(0, 100)}...\n`
      }
    }

    md += "\n---\n\n"
  }

  return md
}
```

**Step 3: Create new bin command (optional)**

Create `bin/cc-reflect-export-seeds` (executable):

```bash
#!/bin/bash
set -euo pipefail

# Export reflection seeds to markdown
# Usage: cc-reflect-export-seeds [filter]
#   filter: all | active | outdated | archived (default: active)

FILTER="${1:-active}"
SESSION_ID=$(bun ~/.claude/reflections/lib/session-id.ts 2>/dev/null | cut -c1-12)

bun ~/.claude/reflections/lib/reflection-state.ts export-markdown "$FILTER"
```

Make executable: `chmod +x bin/cc-reflect-export-seeds`

**Step 4: Add Makefile target** (line 168, after list-seeds):

```makefile
export-seeds:
	@bun lib/reflection-state.ts export-markdown active
```

### ACCEPTANCE CRITERIA

- **Done when**:
  1. ✅ New `export-markdown` case added to CLI switch statement in reflection-state.ts
  2. ✅ `generateMarkdownExport()` function generates valid markdown with all seed fields
  3. ✅ Exported markdown includes: title, status, freshness_tier, anchors, expansions history
  4. ✅ Filter parameter works (all/active/outdated/archived)
  5. ✅ Can run: `bun lib/reflection-state.ts export-markdown active` → outputs markdown to stdout
  6. ✅ Empty seed list handled gracefully (returns markdown with "No seeds found")
  7. ✅ Makefile target works: `make export-seeds`
  8. ✅ All existing tests still pass: `make test`
  9. ✅ No breaking changes to existing CLI operations

### OPTIONAL ENHANCEMENTS

- Add output file support: `bun lib/reflection-state.ts export-markdown active > seeds.md`
- Add export formats: `export-json`, `export-csv`
- Create companion bin command wrapper for easier CLI usage
- Add timestamp to exported filename if file output added

### NOTES

- Markdown should be human-readable (not just a dump)
- Preserve anchor context (file path + surrounding code)
- Include expansion history to show what thought-agents have concluded
- Follow existing pattern: ReflectionStateManager handles logic, CLI case handles invocation