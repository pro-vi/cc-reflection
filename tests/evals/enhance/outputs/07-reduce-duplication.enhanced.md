CONTEXT (Verified Existing):

**File: `lib/reflection-state.ts` (526 lines)**
- CLI handler switch statement (lines 708-992)
- Contains 27 CLI commands with significant duplication:
  - **get-* handlers** (lines 801, 818, 836, 901, 931): All follow pattern `getConfig()` → read property → console.log
  - **set-* handlers** (lines 807, 824, 842, 907, 940): All follow pattern validation → updateConfig() → console.log
  - **cycle-* handlers** (lines 918, 951): All follow pattern getConfig() → rotate array → updateConfig() → console.log

**Duplication patterns identified:**
1. **get-mode** (801-805): `config.expansion_mode`
2. **get-permissions** (818-822): `config.skip_permissions ? "enabled" : "disabled"`
3. **get-haiku** (836-840): `config.use_haiku ? "enabled" : "disabled"`
4. **get-filter** (901-905): `config.menu_filter`
5. **get-context-turns** (931-938): `config.context_turns` with validation fallback

**set-* duplication:**
1. **set-mode** (807-815): Binary validation (interactive|auto)
2. **set-permissions** (824-833): Binary validation (enabled|disabled) + boolean conversion
3. **set-haiku** (842-851): Binary validation (enabled|disabled) + boolean conversion
4. **set-filter** (907-915): Uses isMenuFilter() validator
5. **set-context-turns** (940-948): Numeric range validation (0-20)

**cycle-* duplication:**
1. **cycle-filter** (918-928): Rotates ['active', 'outdated', 'archived', 'all']
2. **cycle-context-turns** (951-960): Rotates [0, 3, 5, 10]

**ReflectionConfig interface (78-86):**
```typescript
interface ReflectionConfig {
  enabled: boolean
  ttl_hours: number
  expansion_mode: "interactive" | "auto"
  skip_permissions: boolean
  use_haiku: boolean
  menu_filter: MenuFilter
  context_turns: number
}
```

**Helper functions available:**
- `parseMenuFilter()` (lines 51-54): Parse and validate filter
- `isMenuFilter()` (lines 45-47): Type guard for MenuFilter

---

ACTION (What to do):

**Refactor CLI handlers to eliminate duplication:**

1. **Create a handler registry object** that defines command metadata:
   - Command name (e.g., "mode", "permissions", "haiku", "filter", "context-turns")
   - Config property key (e.g., "expansion_mode", "skip_permissions")
   - Validator function
   - Getter formatter (optional custom function to format output)
   - Setter converter (optional function to convert value to config value)
   - Cycle order array (if cyclic command)

2. **Extract common patterns into reusable handler factories:**
   - `createGetHandler()`: Handles all "get-X" commands
   - `createSetHandler()`: Handles all "set-X" commands with validation
   - `createCycleHandler()`: Handles all "cycle-X" commands

3. **Replace verbose case statements** with registry-driven logic:
   - Loop through registry to find matching command
   - Call appropriate handler factory with metadata
   - Remove 80+ lines of repetitive case statements

4. **Preserve all validation and business logic:**
   - Same validators, same error messages, same exit codes
   - Same cycle orders and rotation behavior
   - Same config update calls

5. **Update usage documentation** (lines 965-990):
   - Remove duplicate command documentation
   - Keep registry updated as source of truth

---

ACCEPTANCE CRITERIA (REQUIRED):

- Done when all 27 CLI handlers work identically to original implementation
- Done when `bun lib/reflection-state.ts get-mode`, `set-mode interactive`, `cycle-filter` all work correctly
- Done when function line count is ~300-400 lines (vs ~900 lines today)
- Done when unit tests pass (if any exist for CLI handlers)
- Done when git diff shows net negative lines of code (no duplication added)

---

CONSTRAINTS:

- TypeScript only (no language changes)
- Maintain exact same exit codes and error messages for compatibility
- Don't refactor the ReflectionStateManager class itself (only CLI handler section)
- Keep all validation logic intact (isMenuFilter, numeric ranges, etc.)
- Preserve comments about intentional ordering (e.g., cycle-filter note about UX)
