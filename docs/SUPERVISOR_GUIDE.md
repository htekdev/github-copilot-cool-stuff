# Copilot Supervisor Agent - Usage Guide

## Overview

The Copilot Supervisor monitors GitHub Pull Requests and launches comprehensive autonomous review sessions after Copilot finishes coding. It creates a temp folder and launches Copilot CLI with full autonomy to review the PR, verify spec compliance, run tests, validate coverage, and ensure production readiness.

## Quick Start

### Prerequisites

1. **PowerShell** (Core or Desktop)
2. **GitHub CLI** (`gh`) - for authentication
   ```bash
   # Verify installation
   gh --version
   ```
3. **Copilot CLI** - for autonomous reviews
   ```bash
   # Verify installation
   copilot --version
   
   # Should output something like: github-copilot-cli version X.X.X
   ```
   Install from: https://docs.github.com/en/copilot/github-copilot-in-the-cli

### Authentication

Login with GitHub CLI:
```bash
gh auth login
```

Or set a token manually:
```powershell
$env:GITHUB_TOKEN = "your-token-here"
```

### Basic Usage

```powershell
.\scripts\copilot-supervisor.ps1 `
  -Owner htekdev `
  -Repo myproject `
  -PRNumber 42 `
  -SpecFile ./requirements.md
```

### With Custom Poll Interval

```powershell
.\scripts\copilot-supervisor.ps1 `
  -Owner htekdev `
  -Repo myproject `
  -PRNumber 42 `
  -SpecFile ./requirements.md `
  -PollIntervalSeconds 60
```

## How It Works

### 1. Monitoring Phase

The supervisor continuously monitors the PR for Copilot work completion events:
- Tracks `copilot_work_started` events
- Tracks `copilot_work_finished` events
- Triggers review when Copilot finishes a work cycle

### 2. Launch Autonomous Review

When Copilot finishes work:
1. Creates a temporary working folder
2. Launches Copilot CLI in that folder
3. Provides comprehensive review instructions with the spec

### 3. Copilot's Autonomous Review

Copilot uses its full capabilities and GitHub tools to:
- **Checkout the PR** - Uses GitHub tools to access the PR code
- **Examine Changes** - Reviews all code modifications
- **Run Tests** - Executes test suites and validates results
- **Check Coverage** - Verifies code coverage is high (>80%)
- **Verify App Works** - Runs the application to ensure functionality
- **Validate Spec** - Confirms implementation matches requirements
- **Security & Quality** - Identifies vulnerabilities and code issues
- **Post Feedback** - Leaves PR comments if gaps found, or confirms readiness

### 4. Autonomous Decision Making

Copilot makes all decisions on its own and posts comments based on what it finds:

**Fixable Issues** - Uses `@copilot` mention:
- When gaps or issues can be addressed by the coding agent
- Example: "@copilot Please add unit tests for the authentication module to reach 80% coverage"
- Example: "@copilot The login endpoint is missing input validation as specified"

**Critical Issues** - Mentions repository owner:
- When human review or decisions are needed
- The supervisor will use the actual repository owner's username (e.g., @htekdev)
- Example: "@htekdev Critical security vulnerability found - requires human review"
- Example: "@htekdev Architecture decision needed: current approach doesn't scale"

**Production Ready** - No mentions needed:
- When everything passes all checks
- Example: "✅ PR is production-ready. All tests pass, 85% coverage, app verified working."

No scoring, no predefined logic - full Copilot autonomy with clear escalation guidance.

## Specification File Format

Create a markdown file describing your requirements:

```markdown
# Project Requirements

## Feature: User Authentication

**Requirements**:
1. Login endpoint with JWT tokens
2. Secure password hashing
3. Session management

**Acceptance Criteria**:
- Passwords hashed with bcrypt
- JWT tokens expire after 1 hour
- Failed login attempts are rate-limited

## Code Quality Standards
- 80% test coverage
- ESLint passes with no warnings
- All functions documented

## Security Requirements
- No SQL injection vulnerabilities
- All input validated and sanitized
- HTTPS only for production
```

## Best Practices

### Writing Good Specifications

1. **Be Specific**: Clear, measurable requirements
2. **Include Acceptance Criteria**: Define "done"
3. **Specify Standards**: Code quality, security requirements, coverage targets
4. **Document Tests**: Expected test behaviors and coverage goals

### When to Use the Supervisor

✅ **Good Use Cases**:
- Long-running, multi-phase implementations
- Security-critical features
- Complex specifications with many requirements
- When you want Copilot to autonomously verify production readiness

❌ **Not Recommended**:
- Quick bug fixes or trivial changes
- When you want manual review control

## Troubleshooting

### "GitHub token required"
- Run `gh auth login` to authenticate
- Or provide token with `-GithubToken` parameter

### "Spec file not found"
- Verify the path to your specification file
- Use absolute paths or paths relative to script location

### Supervisor doesn't detect Copilot completion
- Verify Copilot is actually working on the PR
- Check PR timeline for `copilot_work_started/finished` events
- Try refreshing with a lower poll interval

## Example Workflow

1. **Setup**: Create your spec file (`requirements.md`)
2. **Launch**: Start the supervisor on your PR
3. **Work**: Copilot implements features
4. **Trigger**: Supervisor detects Copilot finished
5. **Review**: Supervisor launches Copilot for autonomous review
6. **Feedback**: Copilot posts comments if gaps found
7. **Complete**: Copilot confirms when production-ready

## License

MIT
