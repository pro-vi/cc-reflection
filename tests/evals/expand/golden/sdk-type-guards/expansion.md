# Type Safety: SDK Type Guards Underutilized in message-utils.ts

## Context

A prior refactoring session cleaned up 12 type casts in `src/lib/agents/chat/` by adopting AI SDK's exported type guards (`isTextUIPart`, `isToolOrDynamicToolUIPart`, etc.). The pattern discovered:

1. SDK exports type guards that narrow `UIMessagePart` variants
2. After narrowing, properties are typed - no casts needed
3. The `'in'` operator also narrows (e.g., `'name' in error` → `error.name` accessible)

However, **3 casts remain in `src/lib/server/ai/message-utils.ts`** (lines 57, 95, 238) that weren't addressed.

## Evidence Gathered

### SDK Exported Guards (from `node_modules/ai/dist/index.d.ts`)

```typescript
declare function isTextUIPart(part: UIMessagePart<...>): part is TextUIPart;
declare function isFileUIPart(part: UIMessagePart<...>): part is FileUIPart;
declare function isReasoningUIPart(part: UIMessagePart<...>): part is ReasoningUIPart;
declare function isToolUIPart<TOOLS>(part: UIMessagePart<...>): part is ToolUIPart<TOOLS>;
declare function isToolOrDynamicToolUIPart<TOOLS>(part: UIMessagePart<...>): part is ToolUIPart<TOOLS> | DynamicToolUIPart;
declare function getToolName<TOOLS>(part: ToolUIPart<TOOLS>): keyof TOOLS;
declare function getToolOrDynamicToolName(part: ToolUIPart | DynamicToolUIPart): string;
```

### Current Usage Across Codebase

- `isTextUIPart`: Already used in `message-utils.ts:161,183` and `api/stream/+server.ts:59`
- `isToolUIPart`: Already used in `agents/chat/parts.ts:53`
- Custom guards: `src/lib/agents/chat/part-guards.ts` handles DB boundary (`unknown` → typed)

### Cast Analysis for message-utils.ts

**Line 57 - `isUIToolPart` function:**
```typescript
export function isUIToolPart(part: unknown): part is UIToolPart {
  const p = part as { type?: string; toolCallId?: string };  // <-- cast
  return typeof p?.type === 'string' && p.type.startsWith('tool-') && ...
}
```
- **Status**: INTENTIONAL - Custom guard for `unknown` boundary
- **Reason**: SDK's `isToolOrDynamicToolUIPart` requires `UIMessagePart`, not `unknown`. This guard serves the DB/serialization boundary where types are lost.
- **Action**: Keep as-is. JSDoc already references SDK equivalent.

**Line 95 - `filterUIOnlyParts`:**
```typescript
parts: msg.parts.filter((part) => {
  const partType = (part as { type?: string }).type;  // <-- cast
  return !UI_ONLY_PARTS.includes(partType ?? '');
})
```
- **Status**: UNNECESSARY - `msg.parts` is `UIMessage['parts']` = discriminated union
- **Reason**: All `UIMessagePart` variants have `type` property. Cast is defensive against theoretical missing type, but TypeScript knows it's there.
- **Fix**: Direct property access: `part.type`

**Line 238 - Turn content check:**
```typescript
const hasToolCalls = turn.content.some((c) => (c as { type: string }).type === 'tool-call');
```
- **Status**: UNNECESSARY - `turn.content` is `Array<TextPart | ToolCallPart>`
- **Reason**: Both `TextPart` and `ToolCallPart` have `type` property as discriminant.
- **Fix**: Direct property access: `c.type === 'tool-call'`

## Recommendation

### Minimal Changes (2 lines)

1. **Line 95**: Remove cast, access `.type` directly
   ```typescript
   // Before:
   const partType = (part as { type?: string }).type;
   // After:
   const partType = part.type;
   ```

2. **Line 238**: Remove cast, access `.type` directly
   ```typescript
   // Before:
   const hasToolCalls = turn.content.some((c) => (c as { type: string }).type === 'tool-call');
   // After:
   const hasToolCalls = turn.content.some((c) => c.type === 'tool-call');
   ```

### Do NOT Change

- **Line 57**: Keep custom `isUIToolPart` guard - it intentionally handles `unknown` for DB boundary safety where SDK guards don't apply.

### Out of Scope

The reflection seed mentioned `ChatView.svelte` - investigation shows it already uses the proper guards:
```typescript
import { isStoredTextPart, isStoredToolPart } from '$lib/agents/chat/part-guards';
// Used at lines 556-562 for partsJson rendering
```

The `part-guards.ts` module handles the DB→typed boundary correctly with custom guards for `unknown` → `StoredTextPart | StoredToolPart`.

## Meta-Lesson (from seed)

> When integrating typed SDKs, grep for `export function is` in node_modules to discover available guards before writing custom ones.

This is valid guidance. For this codebase:
- **UI parts from SDK** → use SDK guards (`isTextUIPart`, `isToolUIPart`, etc.)
- **DB parts from jsonb** → use custom guards (`isStoredTextPart`, `isStoredToolPart`, `isUIToolPart`)

## Success Criteria

- [ ] Lines 95 and 238 in `message-utils.ts` use direct property access (no casts)
- [ ] Tests pass: `pnpm test src/lib/server/ai/message-utils.test.ts`
- [ ] Type check passes: `pnpm check`
