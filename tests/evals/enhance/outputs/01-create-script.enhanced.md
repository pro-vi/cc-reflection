# Create a cleanup script for old seeds

## Context (Verified Existing)

**Reflection system structure**:
- Storage: `~/.claude/reflections/seeds/` contains 1,927 session directories (each dir is a session ID)
- Each session dir contains seed JSON files (structure defined in `/Users/provi/.claude/reflections/reflection-state.ts`)
- Seed schema (`ReflectionSeed` interface, lines 62-76 in reflection-state.ts):
  - `id`: seed identifier
  - `created_at`: ISO timestamp string
  - `ttl_hours`: configured in `ReflectionConfig` (default 24 hours, line 89)
  - `status`: 'active' (default) or 'archived'
  - `is_outdated`: computed field, true if seed age > ttl_hours
  - `freshness_tier`: emoji tier (🌱 = fresh/current session, 💭 = recent/other sessions, 💤 = outdated/stale, 📦 = archived)

**Existing cleanup infrastructure**:
- `reflection-state.ts` has built-in methods (lines 402-490):
  - `deleteSeed(seedId)`: hard delete (irreversible)
  - `archiveSeed(seedId)`: soft delete (preserves for historical reference, status='archived')
  - `archiveAllSeeds()`: soft delete all seeds in session
  - `archiveOutdatedSeeds()`: soft delete only seeds where is_outdated=true (💤 tier)
  - `deleteArchivedSeeds()`: hard delete all archived seeds (permanent cleanup)
- Existing CLI scripts that use these methods:
  - `bin/cc-reflect-delete-seed`: individual seed deletion with confirmation
  - `bin/cc-reflect-archive-seed`: toggle archive status (archive/unarchive) with confirmation
- Makefile targets (lines 105-118):
  - `make clean-seeds`: remove ALL seeds without filtering
  - `make clean-all`: remove seeds + logs

**Config system** (`~/.claude/reflections/config.json`):
- `ttl_hours`: defines age threshold for "outdated" status (default 24)
- `menu_filter`: which seeds to show ('all', 'active', 'outdated', 'archived')

**Existing logging infrastructure** (`lib/cc-common.sh`):
- `cc_log_info()`, `cc_log_error()` functions
- Logs written to `~/.claude/reflections/logs/cc-reflection.log`

## Action (What to do)

Create a new script `bin/cc-reflect-cleanup-old-seeds` that:

**1. Analyze seed age**:
   - Read all seeds from current session
   - Calculate age for each seed: `(now - created_at) / 1000 / 3600` (convert to hours)
   - Compare against `config.ttl_hours` to determine "outdated" status
   - Use `reflection-state.ts` `is_outdated` field as single source of truth

**2. Categorize seeds**:
   - **Fresh**: created within last `ttl_hours` (🌱 or 💭 tier)
   - **Outdated**: older than `ttl_hours` but not yet archived (💤 tier)
   - **Archived**: status='archived' (📦 tier)

**3. Display analysis**:
   - Show counts: "Fresh: X, Outdated: Y, Archived: Z"
   - Show size of outdated seeds on disk
   - Show estimated storage savings if cleanup executed

**4. Provide cleanup modes** (user selects via CLI flag):
   - `--dry-run` (default): Show what WOULD be cleaned, don't execute
   - `--archive-outdated`: Soft delete (archive) only outdated seeds (💤 → 📦)
   - `--archive-all`: Soft delete all active seeds
   - `--delete-archived`: Hard delete all archived seeds (⚠️ irreversible)
   - `--aggressive`: Archive outdated THEN delete all archived (two-phase cleanup)

**5. Confirmation workflow**:
   - If not `--dry-run`: Show summary, prompt for confirmation
   - Log all actions to `~/.claude/reflections/logs/cc-reflection.log`
   - Report number of seeds affected and storage reclaimed

**Implementation details**:
- Use `reflection-state.ts` methods (already callable via `cc_bun_run`)
- Source `lib/cc-common.sh` for shared utilities (`cc_log_info`, `cc_bun_run`, etc.)
- Follow pattern of existing scripts (`cc-reflect-delete-seed`, `cc-reflect-archive-seed`)
- Output to `/dev/tty` for prompts (so menu can capture stdout/stderr separately)
- Handle edge cases: no outdated seeds, no archived seeds, empty session

**Integration** (after creating script):
- Add `make cleanup` target to Makefile with `--dry-run` default
- Add cleanup modes as Makefile targets: `make cleanup-archive`, `make cleanup-aggressive`

## Acceptance Criteria

Done when:

- ✅ Script `bin/cc-reflect-cleanup-old-seeds` created and executable
- ✅ Supports all four cleanup modes: `--dry-run`, `--archive-outdated`, `--delete-archived`, `--aggressive`
- ✅ Default behavior is `--dry-run` (safe, shows what would happen)
- ✅ Shows clear categorization: Fresh / Outdated / Archived seed counts
- ✅ Shows estimated storage savings (disk size before vs after)
- ✅ Prompts for confirmation before destructive operations
- ✅ Logs all cleanup actions to `cc-reflection.log`
- ✅ Handles edge cases gracefully (no outdated seeds, empty session, etc.)
- ✅ Usage matches existing script patterns (error on /dev/tty, success exit 0)
- ✅ Makefile targets added: `make cleanup` (dry-run), `make cleanup-archive`, `make cleanup-aggressive`

## Out of scope

- Interactive fzf menu integration (use `bin/cc-reflect` for interactive pruning)
- Scheduled/cron cleanup (script is manual for now)
- Cross-session cleanup (cleanup only current session)
- Compression or archival format (no zip/tar, just delete/archive)