<#
.SYNOPSIS
    Supervisor agent that monitors Copilot's work and launches comprehensive PR review sessions.

.DESCRIPTION
    Waits for Copilot to finish coding, then launches a new Copilot CLI session in a temp folder
    to perform a full PR review. Copilot uses its GitHub tools to checkout the PR, verify spec
    compliance, check tests, validate code coverage, and ensure the app works. Posts comments
    on the PR if any gaps are found.

.PARAMETER Owner
    GitHub repository owner

.PARAMETER Repo
    GitHub repository name

.PARAMETER PRNumber
    Pull request number to supervise

.PARAMETER SpecFile
    Path to the specification file that defines requirements

.PARAMETER PollIntervalSeconds
    How often to check PR status (default: 30 seconds)

.PARAMETER GithubToken
    GitHub PAT (uses 'gh auth token' if not provided)

.EXAMPLE
    .\copilot-supervisor.ps1 -Owner htekdev -Repo myrepo -PRNumber 1 -SpecFile ./spec.md
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Owner,
    
    [Parameter(Mandatory=$true)]
    [string]$Repo,
    
    [Parameter(Mandatory=$true)]
    [int]$PRNumber,
    
    [Parameter(Mandatory=$true)]
    [string]$SpecFile,
    
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

# Validate spec file exists
if (-not (Test-Path $SpecFile)) {
    Write-Error "Spec file not found: $SpecFile"
    exit 1
}

# Read spec file content
$specContent = Get-Content $SpecFile -Raw

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
Write-Host "  Copilot Supervisor Agent" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Repository:    $Owner/$Repo"
Write-Host "  PR Number:     #$PRNumber"
Write-Host "  Spec File:     $SpecFile"
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
        Write-Host "*** COPILOT FINISHED - LAUNCHING REVIEW ***" -ForegroundColor Green
        Write-Host ""
        
        # Create temp folder for Copilot session
        $tempFolderPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.Guid]::NewGuid().ToString())
        $tempFolder = New-Item -ItemType Directory -Path $tempFolderPath
        Write-Host "Created temp folder: $($tempFolder.FullName)" -ForegroundColor Gray
        
        try {
            # Change to temp folder
            Push-Location $tempFolder.FullName
            
            # Build comprehensive review prompt for Copilot
            $reviewPrompt = @"
You are a supervisor agent reviewing PR #$PRNumber in $Owner/$Repo.

Your task is to perform a comprehensive review to bring this PR to full production readiness. Use your GitHub tools to checkout the PR, examine the code, run tests, and verify everything works.

SPECIFICATION:
$specContent

YOUR REVIEW CHECKLIST:
1. Checkout the PR and examine all changes
2. Verify the implementation matches the specification requirements
3. Run all tests and ensure they pass
4. Check code coverage is high (aim for >80%)
5. Verify the application actually works (run it if possible)
6. Ensure the specification is well-documented on completion
7. Look for any security vulnerabilities or code quality issues
8. Validate all claims made in commit messages and PR description

If you find any gaps, issues, or missing requirements:
- Post a detailed comment on the PR explaining what needs to be fixed
- Be specific about what's missing or wrong
- Provide actionable feedback

If everything looks good and production-ready:
- Post a comment confirming the PR is ready
- Highlight what was verified (tests passing, coverage, app working, etc.)

Use your full capabilities and GitHub tools to perform this review autonomously. Make all decisions on your own.
"@
            
            Write-Host "Launching Copilot CLI for comprehensive review..." -ForegroundColor Cyan
            Write-Host ""
            
            # Create temp file for prompt to avoid shell injection
            $tempPromptFile = New-TemporaryFile
            $reviewPrompt | Out-File -FilePath $tempPromptFile.FullName -Encoding UTF8
            
            try {
                # Launch Copilot CLI with the review prompt from file
                copilot -p "$(Get-Content $tempPromptFile.FullName -Raw)"
            }
            finally {
                Remove-Item $tempPromptFile.FullName -ErrorAction SilentlyContinue
            }
            
            Write-Host ""
            Write-Host "Review session completed" -ForegroundColor Green
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
