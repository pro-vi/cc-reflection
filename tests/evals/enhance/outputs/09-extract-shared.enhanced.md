# Extract Shared Constants Between Bash and TypeScript

## Context (Verified Existing)

**Key Files**:
- `lib/cc-common.sh` (722 lines) — Central bash utilities
- `lib/reflection-state.ts` — TypeScript state management
- `lib/session-id.ts` — Session ID helpers
- `lib/validators.sh` (181 lines) — Bash validation
- `tests/integration/test_contracts.bats` — Cross-language contract tests
- `tests/unit/test_env_vars.bats` — Environment variable tests (verify exists)

**Current Constants Scattered**:
1. Menu filters: `VALID_MENU_FILTERS` bash array (cc-common.sh:574) ↔ `MENU_FILTERS` TypeScript (reflection-state.ts:42)
2. Freshness tiers: `CC_SEED_EMOJI_PATTERN` bash (cc-common.sh:40) ↔ `FreshnessTier` TypeScript (reflection-state.ts:31)
3. Expansion modes: Validated in bash functions but no centralized constant
4. Permissions modes: "enabled" / "disabled" string literals scattered
5. Haiku modes: "enabled" / "disabled" string literals scattered
6. Default config: `DEFAULT_CONFIG` TypeScript (reflection-state.ts:88) ↔ No bash equivalent
7. Directory paths: Hardcoded in multiple places

**SYNC Comments Already Present** (indicate developer intent for extraction):
- cc-common.sh:38 — "SYNC: Must match FreshnessTier type in lib/reflection-state.ts:31"
- cc-common.sh:572 — "SYNC: Must match MENU_FILTERS constant in lib/reflection-state.ts:42"
- reflection-state.ts:41 — "SYNC: Must match MenuFilter type above and bash VALID_MENU_FILTERS in lib/validators.sh"
- validators.sh:13 — "SYNC: Must match MENU_FILTERS constant in lib/reflection-state.ts:42"

## Action (Create New Constants Module)

### Step 1: Create `lib/constants.ts`

New file: `lib/constants.ts`

Central TypeScript file containing:
- `MENU_FILTERS` (copy from reflection-state.ts)
- `FRESHNESS_TIERS` new array: `['🌱', '💭', '💤', '📦']`
- `EXPANSION_MODES` new array: `['interactive', 'auto']`
- `PERMISSIONS_MODES` new array: `['enabled', 'disabled']`
- `HAIKU_MODES` new array: `['enabled', 'disabled']`
- `CONTEXT_TURNS_RANGE` new object: `{ min: 0, max: 20, default: 3 }`
- `DEFAULT_CONFIG` (move from reflection-state.ts)
- Type guards (already partially exist, consolidate): `isMenuFilter()`, add `isExpansionMode()`, etc.

### Step 2: Create `lib/constants.sh`

New file: `lib/constants.sh`

Bash file containing:
- `VALID_MENU_FILTERS=("all" "active" "outdated" "archived")` (copy from cc-common.sh:574)
- `VALID_FRESHNESS_TIERS=("🌱" "💭" "💤" "📦")` new
- `VALID_EXPANSION_MODES=("interactive" "auto")` new
- `VALID_PERMISSIONS_MODES=("enabled" "disabled")` new
- `VALID_HAIKU_MODES=("enabled" "disabled")` new
- `CONTEXT_TURNS_MIN=0` new
- `CONTEXT_TURNS_MAX=20` new
- `CONTEXT_TURNS_DEFAULT=3` new
- Helper functions for validation (consolidate from validators.sh)

**Note**: These files export constants but remain human-readable (not machine-generated JSON)

### Step 3: Remove Duplication

- **reflection-state.ts**: Import `MENU_FILTERS`, `DEFAULT_CONFIG` from `constants.ts` instead of defining locally
- **cc-common.sh**: Source `constants.sh` and use `VALID_MENU_FILTERS` from there (remove local definition at line 574)
- **validators.sh**: Import `VALID_MENU_FILTERS` from `constants.sh` (update line 13 comment)

### Step 4: Update All Usages

Audit and update to reference centralized constants:
- Replace string literals `"interactive"`, `"auto"` with `EXPANSION_MODES` references
- Replace string literals `"enabled"`, `"disabled"` with `PERMISSIONS_MODES`/`HAIKU_MODES` references
- Replace hardcoded ranges `0-20` with `CONTEXT_TURNS_RANGE`
- Update SYNC comments to reference new central files

### Step 5: Update Tests

- **test_contracts.bats**: Add tests verifying constants are identical between bash/TS
- **test_env_vars.bats**: Verify default values for all constants
- Create new test file (optional): `tests/unit/test_constants.bats` verifying constant arrays match

### Step 6: Update Documentation

- **README.md**: Reference centralized constants in "Architecture" or "Development" section
- **CLAUDE.md**: Document constants extraction decision

## Acceptance Criteria

✓ New files created:
  - `lib/constants.ts` — Single source of truth for TypeScript constants
  - `lib/constants.sh` — Single source of truth for bash constants

✓ Existing files updated (no logic changes, only imports/references):
  - reflection-state.ts imports from constants.ts
  - cc-common.sh sources constants.sh
  - validators.sh updated SYNC comments
  - All SYNC comments point to lib/constants.ts and lib/constants.sh

✓ No duplicated constant definitions remain:
  - Search `grep -n "MENU_FILTERS\|FRESHNESS_TIERS\|EXPANSION_MODES"` finds only definitions in lib/constants.* and usages elsewhere

✓ Tests pass:
  - `make test` succeeds (all 88+ existing tests)
  - New contract tests verify bash/TypeScript constants match

✓ No breaking changes:
  - All bash functions remain in cc-common.sh, validators.sh (unchanged behavior)
  - All TypeScript types remain in reflection-state.ts (unchanged behavior)
  - Constants are extracted, not logic

## Out of Scope

- Refactoring validation functions (stay as-is in validators.sh and cc-common.sh)
- Changing type definitions (only extracting constants)
- Moving TypeScript types to constants.ts (only constants, not interfaces/types)
- Database migration or state format changes
