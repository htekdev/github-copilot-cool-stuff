<#
.SYNOPSIS
    Speckit supervisor agent that monitors coding agent PRs and validates implementations locally.

.DESCRIPTION
    Works within the speckit workflow where specs/planning/tasking are defined locally, then
    implementation is delegated to a coding agent via PR. This script:
    
    1. Waits for the coding agent to finish (checks for unchecked tasks, "still working" mentions)
    2. If PR indicates incomplete work, lets the agent continue
    3. Once PR appears complete, clones/checkouts locally to validate the implementation
    4. Runs tests, verifies acceptance criteria, checks the solution actually works
    5. If issues found: fixes them locally, pushes changes, and reports findings to drift.md
    6. If everything verifiable passes: exits successfully
    
    The drift.md file captures context drift and spec refinements discovered during validation.
    The agent discovers the spec file based on the drift file location (typically in same directory).

.PARAMETER Owner
    GitHub repository owner

.PARAMETER Repo
    GitHub repository name

.PARAMETER PRNumber
    Pull request number to supervise

.PARAMETER DriftFile
    Path to the drift.md file for reporting context drift and spec refinements (created if missing)

.PARAMETER PollIntervalSeconds
    How often to check PR status (default: 30 seconds)

.PARAMETER GithubToken
    GitHub PAT (uses 'gh auth token' if not provided)

.EXAMPLE
    .\copilot-supervisor.ps1 -Owner htekdev -Repo myrepo -PRNumber 1 -DriftFile ./drift.md
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Owner,
    
    [Parameter(Mandatory=$true)]
    [string]$Repo,
    
    [Parameter(Mandatory=$true)]
    [int]$PRNumber,
    
    [Parameter(Mandatory=$true)]
    [string]$DriftFile,
    
    [Parameter(Mandatory=$false)]
    [int]$PollIntervalSeconds = 30,
    
    [Parameter(Mandatory=$false)]
    [string]$GithubToken
)

# Get token from gh CLI if not provided
if (-not $GithubToken) {
    $GithubToken = gh auth token 2>$null
    if (-not $GithubToken) {
        Write-Error "GitHub token required. Run 'gh auth login' or use -GithubToken parameter."
        exit 1
    }
}

# Verify Copilot CLI is available
try {
    $copilotVersion = copilot --version 2>&1
    Write-Host "Using Copilot CLI: $copilotVersion" -ForegroundColor Gray
}
catch {
    Write-Error "Copilot CLI not found. Please install GitHub Copilot CLI from https://docs.github.com/en/copilot/github-copilot-in-the-cli"
    exit 1
}

$headers = @{
    "Authorization" = "Bearer $GithubToken"
    "Accept" = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}

$baseUrl = "https://api.github.com/repos/$Owner/$Repo"

# Resolve drift file path (may not exist yet)
$driftFullPath = [System.IO.Path]::GetFullPath($DriftFile)

function Get-PRTimeline {
    param([int]$PRNum)
    
    $allEvents = @()
    $page = 1
    
    try {
        while ($true) {
            $response = Invoke-WebRequest -Uri "$baseUrl/issues/$PRNum/timeline?per_page=100&page=$page" -Headers $headers -Method Get
            $events = $response.Content | ConvertFrom-Json
            
            if ($events.Count -eq 0) { break }
            
            $allEvents += $events
            
            # Check for next page via Link header
            $linkHeader = $response.Headers["Link"]
            if ($linkHeader -and $linkHeader -is [array]) {
                $linkHeader = $linkHeader[0]
            }
            if (-not $linkHeader -or $linkHeader -notmatch 'rel="next"') { break }
            
            $page++
        }
    }
    catch {
        Write-Warning "Error fetching timeline: $_"
    }
    
    return $allEvents
}

function Get-CopilotWorkStatus {
    param([array]$Timeline)
    
    $startedCount = @($Timeline | Where-Object { $_.event -eq "copilot_work_started" }).Count
    $finishedCount = @($Timeline | Where-Object { $_.event -eq "copilot_work_finished" }).Count
    
    # Push/pop: started = push, finished = pop
    # If counts are equal, Copilot is done
    # If started > finished, still working
    $isDone = $startedCount -eq $finishedCount -and $finishedCount -gt 0
    
    return @{
        IsDone = $isDone
        StartedCount = $startedCount
        FinishedCount = $finishedCount
    }
}

function Get-PRDetails {
    param([int]$PRNum)
    
    try {
        return Invoke-RestMethod -Uri "$baseUrl/pulls/$PRNum" -Headers $headers -Method Get
    }
    catch {
        Write-Warning "Error fetching PR: $_"
        return $null
    }
}

# Main loop
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Speckit Supervisor Agent" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Repository:    $Owner/$Repo"
Write-Host "  PR Number:     #$PRNumber"
Write-Host "  Drift File:    $driftFullPath"
Write-Host "  Poll Interval: ${PollIntervalSeconds}s"
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Get initial state
$pr = Get-PRDetails -PRNum $PRNumber
if (-not $pr) {
    Write-Error "Could not find PR #$PRNumber"
    exit 1
}

Write-Host "Supervising: $($pr.title)" -ForegroundColor Cyan
Write-Host ""

$lastHandledFinishedCount = 0
$firstCheck = $true

while ($true) {
    $timestamp = Get-Date -Format 'HH:mm:ss'
    
    # Check PR state
    $pr = Get-PRDetails -PRNum $PRNumber
    if ($pr.state -ne "open") {
        Write-Host "[$timestamp] PR is no longer open. Exiting." -ForegroundColor Yellow
        break
    }
    
    # Check Copilot work status
    $timeline = Get-PRTimeline -PRNum $PRNumber
    $status = Get-CopilotWorkStatus -Timeline $timeline
    
    Write-Host "[$timestamp] Started: $($status.StartedCount) | Finished: $($status.FinishedCount)" -ForegroundColor Gray
    
    if ($status.IsDone -and $status.FinishedCount -gt $lastHandledFinishedCount) {
        Write-Host ""
        Write-Host "*** COPILOT CODING AGENT FINISHED - LAUNCHING SUPERVISOR ***" -ForegroundColor Green
        Write-Host ""
        
        # Create temp folder for local validation
        try {
            $tempFolderPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.Guid]::NewGuid().ToString())
            $tempFolder = New-Item -ItemType Directory -Path $tempFolderPath -ErrorAction Stop
            Write-Host "Created temp folder: $($tempFolder.FullName)" -ForegroundColor Gray
        }
        catch {
            Write-Error "Failed to create temp folder: $_"
            $lastHandledFinishedCount = $status.FinishedCount
            continue
        }
        
        try {
            # Change to temp folder
            Push-Location $tempFolder.FullName
            
            # Build the supervisor prompt for Copilot - agent decides everything
            $supervisorPrompt = @"
You are a speckit supervisor agent for PR #$PRNumber in $Owner/$Repo.

CONTEXT:
- Specs/planning/tasking are defined locally, implementation is delegated to a coding agent via this PR
- The coding agent has signaled it finished a work session
- Your job is to supervise, validate, and ensure the implementation is complete and working

DRIFT FILE PATH:
$driftFullPath

The drift file location tells you where the spec files are (same directory). Look for spec.md, requirements.md, or similar files in that directory to understand the requirements.

IMPORTANT: The tasks.md file with the implementation task list is only in the PR branch, not locally. You must check the PR files or checkout the branch to see task completion status.

=== YOUR WORKFLOW ===

PHASE 1: CHECK IF CODING AGENT IS ACTUALLY DONE
First, examine the PR to determine if the coding agent has truly completed implementation:
- Check the PR files for tasks.md - look for unchecked task boxes (- [ ])
- Check the PR description for unchecked task boxes
- Check recent comments for signals like "still working", "in progress", "WIP", "not done yet"
- Look at the code changes - are there TODO comments or incomplete implementations?

IF THE CODING AGENT IS NOT DONE:
- Post a comment: "@copilot Please continue working on the remaining tasks. [list specific incomplete items you found]"
- Exit - the script will continue monitoring and call you again when the agent finishes

PHASE 2: LOCAL VALIDATION (only if Phase 1 indicates completion)
Clone and test the implementation locally:
- Clone $Owner/$Repo to this temp folder
- Checkout the PR branch: gh pr checkout $PRNumber
- Build the project and check for errors
- Run all tests
- Verify acceptance criteria from the spec actually work
- Check the implementation matches spec requirements

PHASE 3: FIX ISSUES (if validation finds problems)
If you find issues you can fix:
- Make the code changes
- Commit with a clear message
- Push to the PR branch
- Continue validation

PHASE 4: REPORT FINDINGS
Update the drift file at: $driftFullPath

Format as markdown with these sections:
## Context Drift
(things that changed or differ from the original spec)

## Spec Refinements  
(clarifications or additions the spec needs based on what you learned)

## Validation Results
- Build: [PASS/FAIL]
- Tests: [PASS/FAIL] (X passed, Y failed)
- Acceptance Criteria: [list each and PASS/FAIL]

## Manual Verification Needed
(items requiring human review that you couldn't automatically verify)

## Fixes Applied
(any fixes you made during validation)

PHASE 5: EXIT DECISION
- If everything verifiable passes: Exit with success summary
- If critical issues remain that you cannot fix: Post a comment tagging @$Owner for human review

IMPORTANT: You make ALL decisions. The script just waits for the coding agent to signal completion and launches you.
"@ -replace "`"", "'"
            
            Write-Host "Launching Copilot CLI supervisor session..." -ForegroundColor Cyan
            Write-Host ""
            
            # Launch Copilot CLI to review and decide next steps
            
            $cmd = "copilot -p `$supervisorPrompt --yolo"
            Write-Host "Running: $cmd" -ForegroundColor Gray
            Write-Host ""
            
            Invoke-Expression $cmd
            
            Write-Host ""
            Write-Host "Supervisor session completed" -ForegroundColor Green
        }
        finally {
            # Return to original location and cleanup
            Pop-Location
            Remove-Item -Path $tempFolder.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Mark as handled
        $lastHandledFinishedCount = $status.FinishedCount
        
        Write-Host ""
        Write-Host "Continuing to monitor..." -ForegroundColor Cyan
        Write-Host ""
    }
    
    # Wait before next check (skip on first iteration)
    if ($firstCheck) {
        $firstCheck = $false
    }
    else {
        Start-Sleep -Seconds $PollIntervalSeconds
    }
}
