#!/usr/bin/env bun

/**
 * Reflection State Manager
 *
 * Manages reflection seeds: writing, reading, expiring, deduplicating
 */

import { createHash } from "crypto"
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from "fs"
import { join } from "path"
import { getProjectHash, getReflectionsBaseDirOrThrow, getSessionId } from "./session-id"

// Module-level constant for forbidden characters in seed titles
// WHY: Prevents shell injection + menu-breaking chars. Control chars (\x00-\x1f\x7f) subsume existing \t\n\r
// SYNC: Must match validate_seed_title() in lib/validators.sh
const FORBIDDEN_CHARS = /[\$`'"|;&\\<>(){}\x00-\x1f\x7f]/

export interface ReflectionAnchor {
  path: string
  context_start_text: string
  context_end_text: string
  line_start?: number
  line_end?: number
}

export type SeedStatus = 'active' | 'archived'
export type FreshnessTier = '🌱' | '💭' | '💤' | '📦'
// Filter based on freshness tiers:
// - 'active' = 🌱 + 💭 (fresh + recent thoughts)
// - 'outdated' = 💤 (stale/sleeping)
// - 'archived' = 📦 (manually boxed)
// - 'all' = everything
export type MenuFilter = 'all' | 'active' | 'outdated' | 'archived'

// Canonical list of valid menu filters - single source of truth
// WHY: Prevents validation scatter across CLI commands
// SYNC: Must match MenuFilter type above and bash VALID_MENU_FILTERS in lib/validators.sh
export const MENU_FILTERS: readonly MenuFilter[] = ['all', 'active', 'outdated', 'archived'] as const

// Type guard for runtime validation of MenuFilter
export function isMenuFilter(value: unknown): value is MenuFilter {
  return typeof value === 'string' && MENU_FILTERS.includes(value as MenuFilter)
}

// Parse and validate a filter argument, returning default if invalid
// WHY: DRY validation with configurable default for different CLI commands
export function parseMenuFilter(value: string | undefined, defaultValue: MenuFilter): MenuFilter {
  if (value !== undefined && isMenuFilter(value)) return value
  return defaultValue
}

export interface ExpansionRecord {
  timestamp: string         // ISO string when expanded
  result_path?: string      // Path to expansion result file (standalone flow)
  conclusion: string        // Agent's free-form conclusion (required)
}

export interface ReflectionSeed {
  id: string
  title: string
  rationale: string
  anchors: ReflectionAnchor[]
  options_hint?: string
  ttl_hours: number
  created_at: string
  dedupe_key: string
  session_id: string
  project_hash?: string // 12-char MD5 of project directory; enables cross-conversation listing
  status?: SeedStatus // 'active' (default) or 'archived' (manual)
  is_outdated?: boolean // Computed field: true if seed is older than ttl_hours
  freshness_tier?: FreshnessTier // Computed field: emoji based on status + age + session
  expansions?: ExpansionRecord[] // History of expansions with conclusions
}

export interface ReflectionConfig {
  enabled: boolean
  ttl_hours: number  // Hours before seeds become "outdated" (💤)
  expansion_mode: "interactive" | "auto"
  skip_permissions: boolean
  model: "opus" | "sonnet" | "haiku"
  menu_filter: MenuFilter
  context_turns: number  // Number of recent conversation turns to inject into expand prompt (0 = disabled)
}

const DEFAULT_CONFIG: ReflectionConfig = {
  enabled: true,
  ttl_hours: 72,     // Hours before seeds become "outdated" (💤)
  expansion_mode: "interactive",
  skip_permissions: true,
  model: "opus",
  menu_filter: "active",
  context_turns: 3,  // Default: inject last 3 conversation turns
}

export class ReflectionStateManager {
  private baseDir: string
  private seedsDir: string
  private resultsDir: string
  private configPath: string
  private config: ReflectionConfig
  private sessionId: string
  private projectHash: string

  constructor(sessionIdPrefix: string, baseDir?: string) {
    this.baseDir = baseDir || getReflectionsBaseDirOrThrow()
    this.resultsDir = join(this.baseDir, "results")
    this.configPath = join(this.baseDir, "config.json")
    this.projectHash = getProjectHash()

    // Find session directory using prefix matching (like git commit hashes)
    const matchedSession = this.findSessionByPrefix(sessionIdPrefix)
    this.sessionId = matchedSession
    this.seedsDir = join(this.baseDir, "seeds", matchedSession)

    // Ensure directories exist
    mkdirSync(this.seedsDir, { recursive: true })
    mkdirSync(this.resultsDir, { recursive: true })

    // Load or create config
    this.config = this.loadConfig()
  }

  /**
   * Find session directory by prefix (like git commit hash matching)
   * Returns the full session ID if found, or the original prefix if not found
   */
  private findSessionByPrefix(prefix: string): string {
    const seedsBaseDir = join(this.baseDir, "seeds")

    // If seeds directory doesn't exist, return prefix as-is (will be created)
    if (!existsSync(seedsBaseDir)) {
      return prefix
    }

    // Get all session directories
    const sessions = readdirSync(seedsBaseDir).filter((f) => {
      const stat = statSync(join(seedsBaseDir, f))
      return stat.isDirectory()
    })

    // Check for exact match first (prefer exact over prefix)
    if (sessions.includes(prefix)) {
      return prefix
    }

    // Find prefix matches
    const matches = sessions.filter((s) => s.startsWith(prefix))

    if (matches.length === 0) {
      // No matches - return prefix as-is (new session will be created)
      return prefix
    } else if (matches.length === 1) {
      // Exactly one match - use it!
      return matches[0]
    } else {
      // Multiple matches - this is ambiguous, fail with helpful message
      console.error(`Ambiguous session ID prefix "${prefix}" matches multiple sessions:`)
      matches.forEach((m) => console.error(`  - ${m}`))
      console.error(`Please use a longer prefix to uniquely identify the session.`)
      throw new Error(`Ambiguous session ID prefix: ${prefix}`)
    }
  }

  private loadConfig(): ReflectionConfig {
    if (existsSync(this.configPath)) {
      try {
        const data = readFileSync(this.configPath, "utf-8")
        const parsed = JSON.parse(data)
        // Pick only known keys to drop stale fields (e.g. use_haiku → model migration)
        const merged = { ...DEFAULT_CONFIG, ...parsed }
        const clean: ReflectionConfig = {
          enabled: merged.enabled,
          ttl_hours: merged.ttl_hours,
          expansion_mode: merged.expansion_mode,
          skip_permissions: merged.skip_permissions,
          model: merged.model,
          menu_filter: merged.menu_filter,
          context_turns: merged.context_turns,
        }
        return clean
      } catch (err) {
        console.error("Failed to load reflection config, using defaults:", err)
      }
    }
    // Write default config
    this.saveConfig(DEFAULT_CONFIG)
    return DEFAULT_CONFIG
  }

  private saveConfig(config: ReflectionConfig) {
    writeFileSync(this.configPath, JSON.stringify(config, null, 2))
  }

  /**
   * Generate dedupe key from anchors and title
   */
  private generateDedupeKey(
    title: string,
    anchors: ReflectionAnchor[],
    options_hint?: string
  ): string {
    const anchorStr = anchors
      .map((a) => `${a.path}:${a.context_start_text}`)
      .join("|")
    const input = `${title}:${anchorStr}:${options_hint || ""}`
    return createHash("md5").update(input).digest("hex").substring(0, 12)
  }

  /**
   * Check if seed already exists (deduplication)
   */
  private isDuplicate(dedupeKey: string): boolean {
    const allSeeds = this.listAllSeeds()
    return allSeeds.some((seed) => seed.dedupe_key === dedupeKey)
  }

  /**
   * Write a new reflection seed
   */
  writeSeed(params: {
    title: string
    rationale: string
    anchors: ReflectionAnchor[]
    options_hint?: string
    ttl_hours?: number
  }): { success: boolean; seed?: ReflectionSeed; reason?: string } {
    if (!this.config.enabled) {
      return { success: false, reason: "Reflections disabled" }
    }

    // Validate title for shell injection safety and menu parsing
    if (FORBIDDEN_CHARS.test(params.title)) {
      return {
        success: false,
        reason: `Invalid title: contains forbidden characters ($ \` ' " | ; & \\ < > ( ) { } tab newline)`,
      }
    }

    if (!params.title || params.title.trim().length === 0) {
      return { success: false, reason: "Title cannot be empty" }
    }

    // Generate dedupe key
    const dedupeKey = this.generateDedupeKey(
      params.title,
      params.anchors,
      params.options_hint
    )

    // Check for duplicates
    if (this.isDuplicate(dedupeKey)) {
      return { success: false, reason: "Duplicate seed (same title + anchor)" }
    }

    // Create seed
    const seed: ReflectionSeed = {
      id: `seed-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`,
      title: params.title,
      rationale: params.rationale,
      anchors: params.anchors,
      options_hint: params.options_hint,
      ttl_hours: params.ttl_hours || this.config.ttl_hours,
      created_at: new Date().toISOString(),
      dedupe_key: dedupeKey,
      session_id: this.sessionId,
      project_hash: this.projectHash,
    }

    // Write to disk
    const seedPath = join(this.seedsDir, `${seed.id}.json`)
    writeFileSync(seedPath, JSON.stringify(seed, null, 2))

    return { success: true, seed }
  }

  /**
   * Load, validate, and enrich a single seed from JSON data
   * Returns null if the seed is invalid or should be skipped
   */
  private loadAndValidateSeed(data: string, file: string, filter: MenuFilter): ReflectionSeed | null {
    try {
      const seed = JSON.parse(data) as ReflectionSeed

      // Validate seed structure and content for security
      if (!seed.id || !seed.id.match(/^seed-[0-9]+-[a-z0-9]+$/)) {
        console.error(`Warning: Skipping seed with invalid ID: ${file}`)
        return null
      }

      // Check for shell metacharacters and menu-breaking chars in title
      if (FORBIDDEN_CHARS.test(seed.title)) {
        console.error(`Warning: Skipping seed with unsafe title: ${file}`)
        return null
      }

      // Default status to 'active' if not set
      if (!seed.status) {
        seed.status = 'active'
      }

      // Calculate outdated status
      seed.is_outdated = this.isOutdated(seed)

      // Calculate freshness tier
      seed.freshness_tier = this.getFreshnessTier(seed)

      // Apply filter based on freshness tier
      if (filter === 'active' && (seed.freshness_tier === '💤' || seed.freshness_tier === '📦')) return null
      if (filter === 'outdated' && seed.freshness_tier !== '💤') return null
      if (filter === 'archived' && seed.freshness_tier !== '📦') return null

      return seed
    } catch (err) {
      console.error(`Failed to read seed ${file}:`, err)
      return null
    }
  }

  /**
   * List all seeds for current session
   * @param filter - 'all' | 'active' | 'archived' (default: 'all')
   */
  listSeeds(filter: MenuFilter = 'all'): ReflectionSeed[] {
    // Scan all session directories and return seeds belonging to this project.
    // WHY: Each Claude Code conversation gets a unique UUID, so seeds from
    //      previous conversations live in different session directories.
    //      project_hash (stored on seed since v1.0.1) ties seeds to a project.
    //      Seeds without project_hash (pre-v1.0.1) match only if their
    //      session_id equals the current session (backward compat).
    const all = this.listAllSeeds(filter)
    return all.filter(seed =>
      seed.project_hash === this.projectHash ||
      (!seed.project_hash && seed.session_id === this.sessionId)
    )
  }

  /**
   * List all seeds across all sessions (for global view)
   * @param filter - 'all' | 'active' | 'archived' (default: 'all')
   */
  listAllSeeds(filter: MenuFilter = 'all'): ReflectionSeed[] {
    const seedsBaseDir = join(this.baseDir, "seeds")
    if (!existsSync(seedsBaseDir)) {
      return []
    }

    const sessions = readdirSync(seedsBaseDir).filter((f) => {
      const stat = statSync(join(seedsBaseDir, f))
      return stat.isDirectory()
    })

    const allSeeds: ReflectionSeed[] = []
    for (const session of sessions) {
      const sessionDir = join(seedsBaseDir, session)
      const files = readdirSync(sessionDir).filter((f) => f.endsWith(".json"))

      for (const file of files) {
        const data = readFileSync(join(sessionDir, file), "utf-8")
        const seed = this.loadAndValidateSeed(data, file, filter)
        if (seed) allSeeds.push(seed)
      }
    }

    // Sort by freshness tier (🌱 first, then 💭, then 💤, then 📦), then by timestamp (newest first)
    const tierOrder: Record<FreshnessTier, number> = { '🌱': 0, '💭': 1, '💤': 2, '📦': 3 }
    allSeeds.sort((a, b) => {
      const tierA = tierOrder[a.freshness_tier || '💭']
      const tierB = tierOrder[b.freshness_tier || '💭']
      if (tierA !== tierB) return tierA - tierB
      // Within same tier, sort by timestamp (newest first)
      const tsA = this.extractTimestampFromSeedId(a.id) || 0
      const tsB = this.extractTimestampFromSeedId(b.id) || 0
      return tsB - tsA
    })

    return allSeeds
  }

  /**
   * Get a specific seed by ID
   */
  getSeed(seedId: string): ReflectionSeed | null {
    const allSeeds = this.listAllSeeds()
    return allSeeds.find((s) => s.id === seedId) || null
  }

  /**
   * Delete a seed (after user dismisses or accepts)
   */
  deleteSeed(seedId: string): boolean {
    const allSeeds = this.listAllSeeds()
    const seed = allSeeds.find((s) => s.id === seedId)
    if (!seed) return false

    const seedPath = join(
      this.baseDir,
      "seeds",
      seed.session_id,
      `${seedId}.json`
    )
    if (existsSync(seedPath)) {
      unlinkSync(seedPath)
      return true
    }
    return false
  }

  /**
   * Archive a seed (soft delete - preserves for meta-reflection)
   */
  archiveSeed(seedId: string): boolean {
    const allSeeds = this.listAllSeeds()
    const seed = allSeeds.find((s) => s.id === seedId)
    if (!seed) return false

    const seedPath = join(
      this.baseDir,
      "seeds",
      seed.session_id,
      `${seedId}.json`
    )
    if (existsSync(seedPath)) {
      // Update status to archived
      seed.status = 'archived'
      // Remove computed fields before writing
      delete seed.is_outdated
      delete seed.freshness_tier
      writeFileSync(seedPath, JSON.stringify(seed, null, 2))
      return true
    }
    return false
  }

  /**
   * Unarchive a seed (restore from archived status)
   * WHY: Toggle behavior - Ctrl+A on archived seed restores it
   * Freshness tier will recalculate based on timestamp when listed
   */
  unarchiveSeed(seedId: string): boolean {
    const allSeeds = this.listAllSeeds()
    const seed = allSeeds.find((s) => s.id === seedId)
    if (!seed) return false

    const seedPath = join(
      this.baseDir,
      "seeds",
      seed.session_id,
      `${seedId}.json`
    )
    if (existsSync(seedPath)) {
      // Restore status to active
      seed.status = 'active'
      // Remove computed fields before writing (will recalculate on list)
      delete seed.is_outdated
      delete seed.freshness_tier
      writeFileSync(seedPath, JSON.stringify(seed, null, 2))
      return true
    }
    return false
  }

  /**
   * Archive all seeds (soft delete all)
   * NOTE: Archives all active seeds regardless of current filter setting
   */
  archiveAllSeeds(): number {
    const seeds = this.listSeeds('active')  // Explicitly get active seeds only
    let archived = 0
    for (const seed of seeds) {
      if (this.archiveSeed(seed.id)) {
        archived++
      }
    }
    return archived
  }

  /**
   * Archive only outdated seeds (💤 tier)
   * WHY: Keep fresh seeds (🌱, 💭) but clean up stale ones
   * RETURNS: Number of seeds archived
   */
  archiveOutdatedSeeds(): number {
    // Use 'outdated' filter to get only 💤 seeds
    const seeds = this.listSeeds('outdated')
    let archived = 0
    for (const seed of seeds) {
      if (this.archiveSeed(seed.id)) {
        archived++
      }
    }
    return archived
  }

  /**
   * Delete all archived seeds (permanent cleanup)
   */
  deleteArchivedSeeds(): number {
    const allSeeds = this.listAllSeeds()
    let deleted = 0
    for (const seed of allSeeds) {
      if (seed.status === 'archived' && this.deleteSeed(seed.id)) {
        deleted++
      }
    }
    return deleted
  }

  /**
   * Record an expansion conclusion for a seed
   * WHY: Agent-driven tracking - thought-agent records what it concluded
   * @param seedId - The seed that was expanded
   * @param conclusion - Free-form conclusion sentence
   * @param resultPath - Optional path to the result file
   */
  concludeExpansion(seedId: string, conclusion: string, resultPath?: string): boolean {
    const allSeeds = this.listAllSeeds()
    const seed = allSeeds.find((s) => s.id === seedId)
    if (!seed) return false

    const seedPath = join(
      this.baseDir,
      "seeds",
      seed.session_id,
      `${seedId}.json`
    )
    if (!existsSync(seedPath)) return false

    // Create expansion record
    const record: ExpansionRecord = {
      timestamp: new Date().toISOString(),
      conclusion: conclusion,
      ...(resultPath && { result_path: resultPath })
    }

    // Initialize expansions array if needed
    seed.expansions = seed.expansions || []
    seed.expansions.push(record)

    // Remove computed fields before writing
    delete seed.is_outdated
    delete seed.freshness_tier

    writeFileSync(seedPath, JSON.stringify(seed, null, 2))
    return true
  }

  /**
   * Extract timestamp from seed ID
   * WHY: Seed ID timestamp is system-generated and immutable, more reliable than created_at
   * @param seedId - Seed ID in format "seed-{timestamp}-{random}"
   * @returns Unix timestamp in milliseconds, or null if invalid format
   */
  private extractTimestampFromSeedId(seedId: string): number | null {
    const match = seedId.match(/^seed-(\d+)-[a-z0-9]+$/)
    if (!match) return null
    return parseInt(match[1], 10)
  }

  // Time threshold for fresh tier (in hours)
  private static readonly FRESH_THRESHOLD_HOURS = 24   // 🌱 seedling: < 24 hours

  /**
   * Get seed age in milliseconds
   * WHY: Uses seed ID timestamp (system-generated) instead of created_at (potentially Claude-supplied)
   */
  private getSeedAgeMs(seed: ReflectionSeed): number | null {
    const createdAt = this.extractTimestampFromSeedId(seed.id)
    if (createdAt === null) return null
    return Date.now() - createdAt
  }

  /**
   * Check if seed is fresh (< 24 hours old)
   * WHY: Time-based freshness is reliable across all contexts
   */
  private isFresh(seed: ReflectionSeed): boolean {
    const ageMs = this.getSeedAgeMs(seed)
    if (ageMs === null) return false
    return ageMs < ReflectionStateManager.FRESH_THRESHOLD_HOURS * 60 * 60 * 1000
  }

  /**
   * Check if seed is outdated (past TTL, default 24 hours)
   * WHY: Uses seed ID timestamp (system-generated) instead of created_at (potentially Claude-supplied)
   */
  private isOutdated(seed: ReflectionSeed): boolean {
    const ageMs = this.getSeedAgeMs(seed)
    if (ageMs === null) {
      // Invalid seed ID format - treat as expired (defensive)
      console.error(`Invalid seed ID format: ${seed.id}`)
      return true
    }
    const ttlMs = seed.ttl_hours * 60 * 60 * 1000
    return ageMs > ttlMs
  }

  /**
   * Compute freshness tier emoji for a seed (time-based)
   * 🌱 = fresh seedling (< 24 hours old)
   * 💭 = growing thought (24-72 hours old)
   * 💤 = falling asleep (> 72 hours / past TTL)
   * 📦 = archived (manual)
   */
  private getFreshnessTier(seed: ReflectionSeed): FreshnessTier {
    // Archived takes highest precedence (manual user action)
    if (seed.status === 'archived') return '📦'
    // Fresh = just planted seedling (< 24 hours)
    if (this.isFresh(seed)) return '🌱'
    // Outdated = falling asleep (past TTL, default 72 hours)
    if (seed.is_outdated) return '💤'
    // In between = growing thought bubble (24-72 hours)
    return '💭'
  }

  /**
   * Delete all outdated seeds (permanent cleanup)
   * WHY: Manual cleanup command to remove old seeds past their TTL
   */
  cleanupExpired(): number {
    const allSeeds = this.listAllSeeds()
    let cleaned = 0

    for (const seed of allSeeds) {
      if (this.isOutdated(seed)) {
        if (this.deleteSeed(seed.id)) {
          cleaned++
        }
      }
    }

    return cleaned
  }

  /**
   * Write reflection result (from thought-agent)
   */
  writeResult(seedId: string, expandedPrompt: string): string {
    const resultPath = join(this.resultsDir, `${seedId}-result.md`)
    const timestamp = new Date().toISOString()
    const content = `# Reflection Result
**Seed ID:** ${seedId}
**Expanded At:** ${timestamp}

---

${expandedPrompt}
`
    writeFileSync(resultPath, content)
    return resultPath
  }

  /**
   * Read reflection result
   */
  readResult(seedId: string): string | null {
    const resultPath = join(this.resultsDir, `${seedId}-result.md`)
    if (!existsSync(resultPath)) {
      return null
    }
    return readFileSync(resultPath, "utf-8")
  }

  /**
   * Get current config
   */
  getConfig(): ReflectionConfig {
    return this.config
  }

  /**
   * Update config
   */
  updateConfig(updates: Partial<ReflectionConfig>) {
    this.config = { ...this.config, ...updates }
    this.saveConfig(this.config)
  }
}

// CLI interface for testing
if (import.meta.main) {
  const rawArgs = process.argv.slice(2)

  // Optional baseDir for testing (use --base-dir=/path flag)
  // WHY: Positional heuristic conflicted with commands that take absolute paths (e.g., conclude's result-path)
  const baseDirArg = rawArgs.find(arg => arg.startsWith('--base-dir='))
  const baseDir = baseDirArg ? baseDirArg.split('=')[1] : undefined

  // Filter out the flag from args for command processing
  const args = baseDirArg ? rawArgs.filter(arg => !arg.startsWith('--base-dir=')) : rawArgs
  const command = args[0]

  // Use centralized session ID logic (matches bash implementation)
  // WHY: Single source of truth prevents hash mismatch bugs
  // TESTED BY: tests/test_session_id.bats::bash and TypeScript produce identical session IDs
  const sessionId = getSessionId()

  const manager = new ReflectionStateManager(sessionId, baseDir)

  switch (command) {
    case "write": {
      // Example: bun lib/reflection-state.ts write "Unvalidated input" "Direct req.body usage" "src/api/payments.ts" "router.post('/payments'" "res.json(charge)" "high"
      // Args: title rationale path start end
      const [title, rationale, path, start, end] = args.slice(1)
      const result = manager.writeSeed({
        title,
        rationale,
        anchors: [{ path, context_start_text: start, context_end_text: end }],
      })
      console.log(JSON.stringify(result, null, 2))
      // Exit with non-zero code if validation failed
      if (!result.success) {
        process.exit(1)
      }
      break
    }

    case "list": {
      // Optional filter argument (default: use config)
      const filterArg = args[1]
      const config = manager.getConfig()
      const filter = parseMenuFilter(filterArg, config.menu_filter)
      const seeds = manager.listSeeds(filter)
      console.log(JSON.stringify(seeds, null, 2))
      break
    }

    case "list-all": {
      // Optional filter argument (default: 'all')
      const filterArg = args[1]
      const filter = parseMenuFilter(filterArg, 'all')
      const seeds = manager.listAllSeeds(filter)
      console.log(JSON.stringify(seeds, null, 2))
      break
    }

    case "get": {
      const seedId = args[1]
      const seed = manager.getSeed(seedId)
      console.log(JSON.stringify(seed, null, 2))
      break
    }

    case "delete": {
      const seedId = args[1]
      const success = manager.deleteSeed(seedId)
      console.log(JSON.stringify({ success }))
      if (!success) process.exit(1)
      break
    }

    case "cleanup": {
      const cleaned = manager.cleanupExpired()
      console.log(JSON.stringify({ cleaned }))
      break
    }

    case "write-result": {
      const [seedId, ...promptParts] = args.slice(1)
      const prompt = promptParts.join(" ")
      const path = manager.writeResult(seedId, prompt)
      console.log(JSON.stringify({ path }))
      break
    }

    case "read-result": {
      const seedId = args[1]
      const result = manager.readResult(seedId)
      console.log(result)
      break
    }

    case "get-mode": {
      const config = manager.getConfig()
      console.log(config.expansion_mode)
      break
    }

    case "set-mode": {
      const mode = args[1]
      if (mode !== "interactive" && mode !== "auto") {
        console.error(`Invalid mode: ${mode} (must be "interactive" or "auto")`)
        process.exit(1)
      }
      manager.updateConfig({ expansion_mode: mode as "interactive" | "auto" })
      console.log(mode)
      break
    }

    case "get-permissions": {
      const config = manager.getConfig()
      console.log(config.skip_permissions ? "enabled" : "disabled")
      break
    }

    case "set-permissions": {
      const mode = args[1]
      if (mode !== "enabled" && mode !== "disabled") {
        console.error(`Invalid permissions mode: ${mode} (must be "enabled" or "disabled")`)
        process.exit(1)
      }
      const skipPermissions = mode === "enabled"
      manager.updateConfig({ skip_permissions: skipPermissions })
      console.log(mode)
      break
    }

    case "get-model": {
      const config = manager.getConfig()
      console.log(config.model)
      break
    }

    case "set-model": {
      const model = args[1]
      if (model !== "opus" && model !== "sonnet" && model !== "haiku") {
        console.error(`Invalid model: ${model} (must be "opus", "sonnet", or "haiku")`)
        process.exit(1)
      }
      manager.updateConfig({ model })
      console.log(model)
      break
    }

    case "archive": {
      const seedId = args[1]
      const success = manager.archiveSeed(seedId)
      console.log(JSON.stringify({ success }))
      if (!success) process.exit(1)
      break
    }

    case "unarchive": {
      const seedId = args[1]
      const success = manager.unarchiveSeed(seedId)
      console.log(JSON.stringify({ success }))
      if (!success) process.exit(1)
      break
    }

    case "conclude": {
      const seedId = args[1]
      const conclusion = args[2]
      const resultPath = args[3] // optional
      if (!seedId || !conclusion) {
        console.error("Usage: conclude <seed-id> <conclusion> [result-path]")
        process.exit(1)
      }
      const success = manager.concludeExpansion(seedId, conclusion, resultPath)
      console.log(JSON.stringify({ success }))
      break
    }

    case "archive-all": {
      const archived = manager.archiveAllSeeds()
      console.log(JSON.stringify({ archived }))
      break
    }

    case "archive-outdated": {
      const archived = manager.archiveOutdatedSeeds()
      console.log(JSON.stringify({ archived }))
      break
    }

    case "delete-archived": {
      const deleted = manager.deleteArchivedSeeds()
      console.log(JSON.stringify({ deleted }))
      break
    }

    case "get-filter": {
      const config = manager.getConfig()
      console.log(config.menu_filter)
      break
    }

    case "set-filter": {
      const filter = args[1]
      if (!isMenuFilter(filter)) {
        console.error(`Invalid filter: ${filter} (must be one of: ${MENU_FILTERS.join(', ')})`)
        process.exit(1)
      }
      manager.updateConfig({ menu_filter: filter })
      console.log(filter)
      break
    }

    case "cycle-filter": {
      const config = manager.getConfig()
      const current = config.menu_filter
      // Cycle order: active → outdated → archived → all → active
      // NOTE: Intentionally different order from MENU_FILTERS (UX: most common first)
      const cycleOrder: MenuFilter[] = ['active', 'outdated', 'archived', 'all']
      const currentIdx = cycleOrder.indexOf(current)
      const next = cycleOrder[(currentIdx + 1) % cycleOrder.length]
      manager.updateConfig({ menu_filter: next })
      console.log(next)
      break
    }

    case "get-context-turns": {
      const config = manager.getConfig()
      // Validate that context_turns is a valid number, default to 3 if corrupted
      const value = config.context_turns
      const turns = typeof value === "number" && !isNaN(value) && value >= 0 ? value : 3
      console.log(turns)
      break
    }

    case "set-context-turns": {
      const turns = parseInt(args[1], 10)
      if (isNaN(turns) || turns < 0 || turns > 20) {
        console.error(`Invalid context turns: ${args[1]} (must be 0-20)`)
        process.exit(1)
      }
      manager.updateConfig({ context_turns: turns })
      console.log(turns)
      break
    }

    case "cycle-context-turns": {
      const config = manager.getConfig()
      const current = config.context_turns ?? 3
      // Cycle order: 0 → 3 → 5 → 10 → 0
      const cycleOrder = [0, 3, 5, 10]
      const currentIdx = cycleOrder.indexOf(current)
      const next = currentIdx >= 0 ? cycleOrder[(currentIdx + 1) % cycleOrder.length] : 3
      manager.updateConfig({ context_turns: next })
      console.log(next)
      break
    }

    default:
      console.error(`Unknown command: ${command}`)
      console.log("Usage:")
      console.log("  write <title> <rationale> <path> <start> <end>")
      console.log("  list [all|active|outdated|archived]")
      console.log("  list-all [all|active|outdated|archived]")
      console.log("  get <seedId>")
      console.log("  delete <seedId>")
      console.log("  archive <seedId>")
      console.log("  conclude <seedId> <conclusion> [result-path]")
      console.log("  archive-all")
      console.log("  delete-archived")
      console.log("  cleanup")
      console.log("  write-result <seedId> <expanded-prompt>")
      console.log("  read-result <seedId>")
      console.log("  get-mode")
      console.log("  set-mode <interactive|auto>")
      console.log("  get-permissions")
      console.log("  set-permissions <enabled|disabled>")
      console.log("  get-model")
      console.log("  set-model <opus|sonnet|haiku>")
      console.log("  get-filter")
      console.log("  set-filter <all|active|outdated|archived>")
      console.log("  cycle-filter")
      console.log("  get-context-turns")
      console.log("  set-context-turns <0-20>")
      console.log("  cycle-context-turns")
      process.exit(1)
  }
}
