# Fix mode toggle menu not updating

## Task
The menu should update to show the new expansion mode (Interactive ↔ Auto) immediately after user toggles via the Settings section in cc-reflect.

## Current Behavior
- User selects "🔄 Mode: Interactive (→ Auto)" in the Settings section
- Toggle succeeds (config updated)
- Menu reloads but still shows old mode

## Expected Behavior
- After toggle and menu reload, Settings section should display the new mode:
  - If was "Interactive" → should show "🔄 Mode: Auto (→ Interactive)"
  - If was "Auto" → should show "🔄 Mode: Interactive (→ Auto)"

## Investigation Findings

The flow when user toggles mode (cc-reflect lines 181-188):
```bash
elif [ "$cmd" = "cc-reflect-toggle-mode" ]; then
    cc_log_info "Toggling expansion mode..."
    cc-reflect-toggle-mode > /dev/null
    if [ $? -eq 0 ]; then
        cc_log_info "Mode toggled, rebuilding menu..."
        continue  # Loop back to rebuild menu
    else
        echo "Failed to toggle mode"
        echo "Press Enter to return..."
        read
        continue
    fi
fi
```

The menu rebuilds on each loop iteration at cc-reflect line 100:
```bash
MENU=$("$REFLECTION_BIN/cc-reflect-build-menu" "$FILE")
```

The mode is read fresh in cc-reflect-build-menu line 25:
```bash
EXPANSION_MODE=$(cc_get_expansion_mode)
```

The Settings section is built in lib/menu-utils.sh cc_build_settings_menu() which uses the passed mode parameter.

## Key Code Locations
- **Toggle execution**: bin/cc-reflect-toggle-mode (43 lines) - calls cc_set_expansion_mode via reflection-state.ts
- **Menu rebuild trigger**: bin/cc-reflect line 100 - calls cc-reflect-build-menu
- **Mode read**: bin/cc-reflect-build-menu line 25 - calls cc_get_expansion_mode
- **Settings display**: lib/menu-utils.sh line 256 - printf of mode display
- **Mode get/set functions**: lib/cc-common.sh lines 414-450 - use reflection-state.ts

## Success Criteria
Done when:
1. User toggles mode in Settings menu
2. Menu reloads with `continue`
3. Settings section displays the NEW mode (not cached/stale)
4. All toggle scenarios work: Interactive→Auto and Auto→Interactive
5. Mode persists correctly (verify via subsequent menu reloads)
