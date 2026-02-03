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

## License

MIT
