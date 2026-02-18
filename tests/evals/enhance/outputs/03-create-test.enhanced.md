**CONTEXT (Verified Existing):**

Menu builder is a modular system with two key components:

1. **`lib/menu-utils.sh`** (376 lines) - Menu construction library with testable functions:
   - `cc_section_header()` - Build section dividers with ANSI styling
   - `cc_build_editor_menu()` - Detect and format available editors (vim, VS Code, Cursor, Windsurf)
   - `cc_build_seed_menu()` - Format reflection seeds with emojis and commands
   - `cc_build_enhance_entry()` - Prompt enhancement entry
   - `cc_build_settings_menu()` - Settings toggles (mode, model, filter, context, permissions)
   - `cc_build_actions_menu()` - Destructive actions (archive outdated seeds)
   - `cc_prepare_menu_display()` - Extract labels for fzf display
   - `cc_find_menu_line()` - Find full menu entry from selected label
   - `cc_build_complete_menu()` - Compose full menu with all sections

2. **`bin/cc-reflect-build-menu`** (41 lines) - Menu builder script:
   - Gets mode settings (expansion, permissions, haiku, filter, context)
   - Loads reflection seeds from state manager
   - Calls `cc_build_complete_menu()` to generate full menu

3. **`bin/cc-reflect-rebuild-menu`** (39 lines) - Menu display script:
   - Calls `cc-reflect-build-menu` to build full menu
   - Calls `cc_prepare_menu_display()` to extract labels-only for fzf

**Existing test coverage:**

- `tests/unit/test_menu_utils.bats` - 48+ tests for menu building functions
  - Editor detection, seed menu formatting, menu structure
- `tests/unit/test_menu_parsing.bats` - 26+ tests for menu command extraction
  - Tab-separated format parsing, edge cases, whitespace handling
- `tests/integration/test_menu_scripts.bats` - Integration tests for cc-reflect-build-menu and cc-reflect-rebuild-menu

Test files use BATS (Bash Automated Testing System) with test helpers: bats-support, bats-assert, bats-file (available in `tests/test_helper/`).

---

**ACTION:**

Write comprehensive unit tests for the **complete menu builder** (`cc_build_complete_menu()` function) in a new file: `tests/unit/test_menu_builder_complete.bats`

This function is the orchestrator that combines all menu sections. Tests should verify:

1. **Menu structure integrity**:
   - Always includes editor menu (no header)
   - Always includes enhance prompt entry
   - Always includes settings section with header
   - Always includes actions section with header
   - Conditionally includes seeds section (only if seeds exist)
   - Sections appear in correct order

2. **Conditional section rendering**:
   - Seeds section missing when seeds_json is empty string ""
   - Seeds section missing when seeds_json is "[]" (JSON array)
   - Seeds section appears with correct header when seeds exist
   - Settings and actions always present regardless of seed count

3. **Parameter passing**:
   - Correct mode passed to `cc_build_seed_menu()`
   - Correct mode passed to `cc_build_enhance_entry()`
   - All settings parameters passed to `cc_build_settings_menu()`
   - Safe file path used in editor entries

4. **Dynamic headers**:
   - Seeds header changes based on filter mode:
     - "Seeds (Active 🌱💭)" when filter="active"
     - "Seeds (Outdated 💤)" when filter="outdated"
     - "Seeds (Archived 📦)" when filter="archived"
     - "Seeds (All)" when filter="all"
     - "Seeds" as fallback for unknown filters

5. **Tab separation consistency**:
   - All menu entries use tab separator (visible in test output)
   - Menu entries can be parsed with `cc_parse_menu_command()`

6. **Edge cases**:
   - Default values for missing mode parameter (interactive)
   - Default values for missing permission/haiku/filter/context parameters
   - Handles seeds with empty title (should not crash)
   - Handles very long seed titles (should not truncate or wrap)
   - Handles special characters in seed titles

7. **Empty state behavior**:
   - Editors always present (not in seed state)
   - Enhance entry always present
   - Settings always present
   - Actions always present
   - Entire menu is non-empty even with no seeds

8. **Integration with component functions**:
   - Output can be piped to `cc_prepare_menu_display()` without errors
   - Full menu entries can be parsed with `cc_find_menu_line()`
   - Commands extracted from menu entries are executable strings (not empty, contain spaces only in args)

---

**ACCEPTANCE CRITERIA:**

1. Create new file: `tests/unit/test_menu_builder_complete.bats`
2. Implement at least 25 test cases covering the 8 areas above
3. All tests pass: `make test-unit` shows 100% pass rate for new test file
4. Tests verify behavior, not implementation (use output checks, not internal state inspection)
5. Tests run independently (no dependencies between test cases)
6. Done when: `bun test` and `make test` both pass with new menu builder tests included
