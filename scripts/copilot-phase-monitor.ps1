<#
.SYNOPSIS
    Monitors a PR for Copilot completion and launches a review session.

.DESCRIPTION
    Watches a PR for the 'copilot_work_finished' event. When detected, launches
    a new Copilot CLI session to review the PR and decide next steps.

.PARAMETER Owner
    GitHub repository owner

.PARAMETER Repo
    GitHub repository name

.PARAMETER PRNumber
    Pull request number to monitor

.PARAMETER PollIntervalSeconds
    How often to check PR status (default: 30 seconds)

.PARAMETER GithubToken
    GitHub PAT (uses 'gh auth token' if not provided)

.EXAMPLE
    .\copilot-phase-monitor.ps1 -Owner htekdev -Repo devplatform-finops-agent -PRNumber 1
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Owner,
    
    [Parameter(Mandatory=$true)]
    [string]$Repo,
    
    [Parameter(Mandatory=$true)]
    [int]$PRNumber,
    
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

$headers = @{
    "Authorization" = "Bearer $GithubToken"
    "Accept" = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}

$baseUrl = "https://api.github.com/repos/$Owner/$Repo"

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

# The prompt to send to Copilot when work is finished
$reviewPrompt = @"
Review PR #$PRNumber in $Owner/$Repo.

Check the PR against docs/PLAN.md to see what phase we're on and what still needs to be done.

If there's more work to do:
- Post a comment on the PR with '@copilot <description of the next task to implement>'

If the current phase looks complete and there are more phases:
- Post a comment on the PR with '@copilot Phase X is complete. Please implement Phase Y: <description from PLAN.md>'

If everything in PLAN.md is done:
- Let me know the implementation is complete so I can review and test locally
"@

# Main loop
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Copilot Work Monitor" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Repository: $Owner/$Repo"
Write-Host "  PR Number:  #$PRNumber"
Write-Host "  Poll interval: ${PollIntervalSeconds}s"
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Get initial state
$pr = Get-PRDetails -PRNum $PRNumber
if (-not $pr) {
    Write-Error "Could not find PR #$PRNumber"
    exit 1
}

Write-Host "Monitoring: $($pr.title)" -ForegroundColor Cyan
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
        Write-Host "*** COPILOT FINISHED! ***" -ForegroundColor Green
        Write-Host ""
        Write-Host "Launching Copilot to review PR and determine next steps..." -ForegroundColor Cyan
        Write-Host ""
        
        # Launch Copilot CLI to review and decide next steps
        $cmd = "copilot --yolo -p `"$reviewPrompt`""
        Write-Host "Running: $cmd" -ForegroundColor Gray
        Write-Host ""
        
        Invoke-Expression $cmd
        
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
