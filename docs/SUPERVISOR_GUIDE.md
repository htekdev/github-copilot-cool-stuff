# Copilot Supervisor Agent - Usage Guide

## Overview

The Copilot Supervisor is an intelligent agent that monitors GitHub Pull Requests and provides automated quality reviews of Copilot's work. It acts as a proxy for the user, ensuring high-quality code delivery while minimizing human intervention.

## Quick Start

### Prerequisites

1. **PowerShell** (Core or Desktop)
2. **GitHub CLI** (`gh`) - for authentication
3. **Copilot CLI** - for AI-powered reviews
4. **GitHub Personal Access Token** (PAT) with appropriate permissions

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
  -SpecFile ./requirements.md `
  -EscalateToUser htekdev
```

### With Custom Poll Interval

```powershell
.\scripts\copilot-supervisor.ps1 `
  -Owner htekdev `
  -Repo myproject `
  -PRNumber 42 `
  -SpecFile ./requirements.md `
  -EscalateToUser htekdev `
  -PollIntervalSeconds 60
```

## How It Works

### 1. Monitoring Phase

The supervisor continuously monitors the PR for Copilot work completion events:
- Tracks `copilot_work_started` events
- Tracks `copilot_work_finished` events
- Triggers review when Copilot finishes a work cycle

### 2. Context Gathering

When Copilot finishes work, the supervisor gathers comprehensive context:
- **PR Diff**: All code changes in the PR
- **Comments**: All discussion and feedback
- **Commits**: Commit history and messages
- **Files Changed**: List of modified files with change statistics
- **Spec File**: Your requirements specification

### 3. Multi-Dimensional Review

The supervisor performs an AI-powered review across three dimensions:

#### Spec Compliance (0-100)
- Does the implementation match requirements?
- Are all specified features implemented?
- Are acceptance criteria met?

#### Code Quality (0-100)
- Is code well-structured and maintainable?
- Does it follow best practices?
- Are there code smells or anti-patterns?

#### Security (0-100)
- Are there security vulnerabilities?
- Is input properly validated?
- Are credentials handled securely?

### 4. Decision Making

Based on the review results, the supervisor decides:

#### ✅ Continue (Avg Score ≥ 90)
- All quality dimensions meet standards
- Posts approval comment
- Lets Copilot proceed to next task

#### 🔧 Fix (70 ≤ Avg Score < 90)
- Issues identified that can be addressed
- Posts feedback with `@copilot` mention
- Provides specific guidance on fixes needed

#### 🚨 Escalate (Avg Score < 70 or Critical Issues)
- Critical issues detected
- Work appears stuck or incomplete
- Posts comment with `@username` mention
- Requests human review on affected files

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
3. **Specify Standards**: Code quality, security requirements
4. **Prioritize**: Mark critical vs. nice-to-have features

### When to Use the Supervisor

✅ **Good Use Cases**:
- Long-running, multi-phase implementations
- Security-critical features
- Complex specifications with many requirements
- When you want to minimize interruptions

❌ **Not Recommended**:
- Quick bug fixes or trivial changes
- Exploratory/experimental work
- When immediate human judgment is needed

## Troubleshooting

### "GitHub token required"
- Run `gh auth login` to authenticate
- Or provide token with `-GithubToken` parameter

### "Spec file not found"
- Verify the path to your specification file
- Use absolute paths or paths relative to script location

### Review fails or returns no JSON
- Check Copilot CLI is installed: `copilot --version`
- Verify PR has actual changes to review
- Check network connectivity to GitHub

### Supervisor doesn't detect Copilot completion
- Verify Copilot is actually working on the PR
- Check PR timeline for `copilot_work_started/finished` events
- Try refreshing with a lower poll interval

## Example Workflow

1. **Setup**: Create your spec file (`requirements.md`)
2. **Launch**: Start the supervisor on your PR
3. **Work**: Copilot implements features based on tasks
4. **Review**: Supervisor reviews each completion cycle
5. **Iterate**: Copilot addresses feedback automatically
6. **Escalate**: Human reviews only when critical issues arise
7. **Complete**: Supervisor confirms all requirements met

## License

MIT
