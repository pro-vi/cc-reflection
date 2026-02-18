# Add Input Validation to Seed Creation

## Context
The seed creation flow in `lib/reflection-state.ts` currently accepts any input without validation. The `write` command handler at line 89 passes title and rationale directly to `writeSeed()` without checking for malicious content or format issues.

## Task
Add comprehensive input validation to the seed creation CLI command to prevent:
1. Shell injection via special characters in title
2. Empty or whitespace-only titles
3. Excessively long titles (>200 chars)
4. Invalid characters that could break menu parsing

## Files to Modify

### `lib/reflection-state.ts`
- Add `validateSeedTitle()` function before line 89
- Call validation in the `write` command handler
- Return meaningful error messages

### `lib/validators.sh`
- The `validate_safe_title()` function already exists - ensure TypeScript validation matches

```typescript
function validateSeedTitle(title: string): { valid: boolean; error?: string } {
  if (!title || title.trim().length === 0) {
    return { valid: false, error: "Title cannot be empty" };
  }
  if (title.length > 200) {
    return { valid: false, error: "Title must be under 200 characters" };
  }
  const dangerous = /[|$`'";&\\<>(){}]/;
  if (dangerous.test(title)) {
    return { valid: false, error: "Title contains invalid characters" };
  }
  return { valid: true };
}
```

## Acceptance Criteria
- Done when: `bun lib/reflection-state.ts write "" "test"` returns error instead of creating seed
- Done when: Titles with `|` or `$` are rejected
- All existing tests in `tests/unit/test_validators.bats` still pass
- Verify by running `make test`

## Constraints
- Must match existing validation in `lib/validators.sh` for consistency
- Error messages should be actionable (tell user what's wrong)
- Don't break existing valid seed creation
