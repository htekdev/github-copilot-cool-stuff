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

Supervisor agent that monitors Copilot's work and launches comprehensive PR review sessions. After Copilot finishes coding, it creates a temp folder and launches Copilot CLI with full autonomy to review the PR, verify spec compliance, check tests, validate coverage, and ensure production readiness.

**Usage:**
```powershell
.\scripts\copilot-supervisor.ps1 `
  -Owner <owner> `
  -Repo <repo> `
  -PRNumber <pr-number> `
  -SpecFile <path-to-spec-file>
```

**Features:**
- **Monitors Copilot Work**: Watches for \copilot_work_started\ and \copilot_work_finished\ events
- **Launches Autonomous Review**: Creates temp folder and launches Copilot CLI with comprehensive review instructions
- **Full Copilot Autonomy**: Copilot uses its GitHub tools to checkout PR, run tests, verify coverage, and validate app works
- **Spec Compliance**: Copilot verifies implementation matches all specification requirements
- **Production Readiness**: Ensures tests pass, code coverage is high, app works, and spec is well-documented
- **Autonomous Feedback**: Copilot decides on its own whether to post comments on gaps or confirm PR is ready

**How It Works:**
1. Monitors PR for Copilot completion events
2. When Copilot finishes, creates a temporary working folder
3. Launches Copilot CLI in that folder with comprehensive review instructions
4. Copilot autonomously:
   - Checks out the PR
   - Examines all code changes
   - Runs tests and validates coverage
   - Verifies the app actually works
   - Validates spec compliance
   - Posts comments on PR if gaps found
   - Confirms readiness if everything looks good

**Documentation:**
- [Comprehensive Usage Guide](docs/SUPERVISOR_GUIDE.md)
- [Example Specification](examples/sample-spec.md)

## License

MIT
