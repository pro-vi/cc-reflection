# Changelog

All notable changes to CC-Reflection will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- GitHub Actions CI workflow for automated testing
- CONTRIBUTING.md with development guidelines
- This CHANGELOG

### Changed
- Simplified installation to single `./install.sh` command
- Removed phantom plugin marketplace references from documentation

## [0.2.0] - 2025-12-21

### Added
- Enhanced reflection expansion modes (interactive/auto toggle)
- 72-hour TTL cycle for seed freshness (was 24 hours)
- `extract-transcript` utility for conversation analysis
- Freshness tier indicators: fresh seedling, thought bubble, sleeping, archived
- Archive management commands (`archive-all`, `archive-outdated`, `delete-archived`)
- Context injection for expansion prompts (`context_turns` config option)

### Changed
- **Breaking:** Freshness tier thresholds changed:
  - Fresh seedling: < 24 hours (unchanged)
  - Thought bubble: 24-72 hours (was 3-24 hours)
  - Sleeping/outdated: > 72 hours (was > 24 hours)
- Default TTL increased from 24 to 72 hours

### Fixed
- Session ID consistency between bash and TypeScript
- Menu parsing with colons in seed titles (now uses `|` separator)

## [0.1.0] - 2025-11-12

### Added
- Initial release
- Reflection skill for Claude Code
- State management system with TTL and deduplication
- Editor hook integration (Ctrl+G menu)
- Thought-agent expansion workflow
- Interactive and auto expansion modes
- Security: shell injection prevention, command allowlisting
- Comprehensive test suite (BATS)
