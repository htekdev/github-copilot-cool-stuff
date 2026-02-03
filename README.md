# GitHub Copilot Cool Stuff

A collection of useful tools and scripts for working with GitHub Copilot.

## Scripts

### copilot-phase-monitor.ps1

Monitors a PR for Copilot completion and launches a review session. Useful for orchestrating multi-phase Copilot implementations.

**Usage:**
```powershell
.\scripts\copilot-phase-monitor.ps1 -Owner <owner> -Repo <repo> -PRNumber <pr-number>
```

**Features:**
- Watches for \copilot_work_started\ and \copilot_work_finished\ events
- Automatically launches Copilot CLI to review when work completes
- Determines next steps based on PLAN.md

### copilot-supervisor.ps1

Supervisor agent that acts as a proxy for the user, reviewing Copilot's work against specifications and providing intelligent feedback. Only escalates to humans when necessary.

**Usage:**
```powershell
.\scripts\copilot-supervisor.ps1 `
  -Owner <owner> `
  -Repo <repo> `
  -PRNumber <pr-number> `
  -SpecFile <path-to-spec-file> `
  -EscalateToUser <github-username>
```

**Features:**
- **Multi-dimensional Quality Review**: Evaluates spec compliance, code quality, and security
- **Intelligent Feedback**: Provides actionable feedback to Copilot to continue or fix issues
- **Smart Escalation**: Only involves humans when critical issues are detected or work is stuck
- **Comprehensive Context**: Reviews PR diff, comments, commits, and files changed
- **Automated Decision Making**: Determines whether work is complete, needs fixes, or requires escalation

**Review Dimensions:**
1. **Spec Compliance** - Validates implementation matches specification requirements
2. **Code Quality** - Assesses code structure, maintainability, and best practices
3. **Security** - Identifies vulnerabilities and security concerns

**Actions:**
- `continue` - Work is complete and meets all quality standards (posts approval comment)
- `fix` - Issues identified that Copilot can address (posts feedback with @copilot mention)
- `escalate` - Critical issues or stuck state requiring human intervention (mentions user + requests file review)

**Documentation:**
- [Comprehensive Usage Guide](docs/SUPERVISOR_GUIDE.md)
- [Example Specification](examples/sample-spec.md)

## License

MIT
