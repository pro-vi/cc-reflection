# Contributing to CC-Reflection

Thank you for your interest in contributing to CC-Reflection!

## Development Setup

### Prerequisites

- [Bun](https://bun.sh) runtime
- `fzf` for menu interface
- `tmux` for session management
- [Claude Code](https://docs.claude.com/en/docs/claude-code)

### Clone with Submodules

The test framework (BATS) is included as git submodules:

```bash
git clone --recurse-submodules https://github.com/pro-vi/cc-reflection
cd cc-reflection
bun install
```

If you already cloned without submodules:

```bash
git submodule update --init --recursive
```

## Running Tests

```bash
# Run all tests
make test

# Run unit tests only
make test-unit

# Run integration tests only
make test-integration

# Run security tests only
make test-security

# Watch mode (requires entr)
make test-watch
```

## Code Style

- Shell scripts follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- TypeScript uses the project's existing patterns
- Run `shellcheck` on bash scripts when available

## Making Changes

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Run tests: `make test`
5. Commit with descriptive message
6. Push to your fork
7. Open a Pull Request

## Pull Request Process

1. Ensure all tests pass
2. Update documentation if needed
3. Add tests for new functionality
4. Keep PRs focused on a single change

## Reporting Issues

- Use GitHub Issues for bug reports and feature requests
- For security vulnerabilities, see [SECURITY.md](./SECURITY.md) or use GitHub Security Advisories

## Questions?

Open a GitHub Issue with the `question` label.
