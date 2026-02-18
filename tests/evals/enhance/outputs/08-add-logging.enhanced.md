CONTEXT (Verified Existing):

**lib/ directory** - All shell scripts use cc-common.sh for centralized logging:
- `lib/cc-common.sh` (lines 9-32): Full logging infrastructure with `cc_log_info()`, `cc_log_warn()`, `cc_log_error()`, `cc_log_debug()` - logs to `~/.claude/reflections/logs/cc-reflection.log` with timestamps and caller info
- `lib/validators.sh`: Sources cc-common.sh, uses `cc_log_*()` for validation feedback
- `lib/menu-utils.sh`: Sources cc-common.sh, uses `cc_log_debug()` for editor detection
- `lib/prompt-builder.sh`: Sources cc-common.sh for `cc_get_context_turns()`

**bin/ directory** - Mix of logging patterns:
- **WITH logging**: `cc-reflect-toggle-mode`, `cc-reflect-delete-seed` - both source `lib/cc-common.sh` and call `cc_log_*()` functions (lines 18-19 and 36, 40, 74, 77)
- **WITHOUT logging**: Need to verify: `cc-reflect-toggle-permissions`, `cc-reflect-toggle-haiku`, `cc-reflect-toggle-filter`, `cc-reflect-toggle-context`, `cc-reflect-archive-seed`, `cc-reflect-preview-seed`, `cc-reflect-build-menu`, `cc-reflect-header`, `cc-reflect-rebuild-menu`, `cc-reflect-expand`

**Goal**: Ensure ALL shell scripts in lib/ and bin/ consistently use the centralized logging infrastructure from cc-common.sh for:
- Function entry/exit
- Parameter validation results
- File operations
- External command execution
- Decision points (conditionals)
- Error handling
- Success/completion events

ACTION (What to do):

**Phase 1: Audit** - Identify which bin/ scripts lack logging integration:
1. Check each remaining `bin/cc-reflect-*` script for `source.*cc-common.sh` and `cc_log_*()` calls
2. Document which scripts are missing logging infrastructure
3. Categorize by type: toggle scripts, action scripts, utility scripts

**Phase 2: Add logging to lib/** (if gaps exist):
1. Review `lib/prompt-builder.sh` for functions that don't log their operations
2. Add `cc_log_debug()` at function entry points
3. Add `cc_log_info()` for significant state changes
4. Add `cc_log_error()` before any `return 1` or `exit` calls

**Phase 3: Add logging to bin/**:
1. For each bin script missing `source "$SCRIPT_DIR/../lib/cc-common.sh"`:
   - Add sourcing after initial setup/symlink resolution (after SCRIPT_DIR is determined)
2. Add `cc_log_info()` at script start with brief description
3. Add `cc_log_debug()` before key operations (reading files, parsing JSON, etc.)
4. Add `cc_log_error()` before error exits
5. Add `cc_log_debug()` before successful completion
6. Ensure every `return 1` or `exit 1` has corresponding `cc_log_error()`

**Standard logging patterns to implement**:
```bash
# At script start
cc_log_info "Script started: $(basename "$0")"

# Before key operations
cc_log_debug "Reading seed: $SEED_ID"

# On errors
cc_log_error "Failed to parse JSON: $SEED_JSON"
return 1

# Before success
cc_log_debug "Seed updated successfully"
```

ACCEPTANCE CRITERIA (REQUIRED):

Done when:
- ✓ All shell scripts in lib/ source cc-common.sh for logging
- ✓ All shell scripts in bin/ source cc-common.sh for logging
- ✓ Every function/script has entry logging (cc_log_info or cc_log_debug at start)
- ✓ Every error path has `cc_log_error()` before return/exit
- ✓ Key decision points log their outcomes (cc_log_debug for conditionals)
- ✓ File operations log their activity (read/write/delete)
- ✓ `cc_log_*` calls include meaningful context (filenames, IDs, values)
- ✓ All tests still pass (ensure logging doesn't break functionality)
- ✓ Centralized log file appears at `~/.claude/reflections/logs/cc-reflection.log` with entries from all scripts

CONSTRAINTS:

- Use ONLY the existing cc_log_info/warn/error/debug functions (no custom logging)
- Don't add logging to TypeScript files (lib/*.ts) - they have separate logging
- Preserve exact symlink resolution logic (SCRIPT_PATH/SCRIPT_DIR handling)
- All logging is append-only (no truncation or overwrites)
- Logging should not produce stdout/stderr except in error cases
