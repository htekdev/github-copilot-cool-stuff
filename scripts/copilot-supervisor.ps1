<#
.SYNOPSIS
    Supervisor agent that reviews Copilot's PR work against user specs and provides feedback.

.DESCRIPTION
    Acts as a proxy for the user by monitoring PR changes, validating against spec files,
    performing multi-dimensional quality reviews (spec compliance, code quality, security),
    and providing actionable feedback to Copilot. Only escalates to humans when necessary.

.PARAMETER Owner
    GitHub repository owner

.PARAMETER Repo
    GitHub repository name

.PARAMETER PRNumber
    Pull request number to supervise

.PARAMETER SpecFile
    Path to the specification file that defines requirements

.PARAMETER EscalateToUser
    GitHub username to @mention when escalation is needed

.PARAMETER PollIntervalSeconds
    How often to check PR status (default: 30 seconds)

.PARAMETER GithubToken
    GitHub PAT (uses 'gh auth token' if not provided)

.EXAMPLE
    .\copilot-supervisor.ps1 -Owner htekdev -Repo myrepo -PRNumber 1 -SpecFile ./spec.md -EscalateToUser htekdev
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
    
    [Parameter(Mandatory=$true)]
    [string]$EscalateToUser,
    
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

function Get-PRDiff {
    param([int]$PRNum)
    
    try {
        $response = Invoke-WebRequest -Uri "$baseUrl/pulls/$PRNum" -Headers @{
            "Authorization" = "Bearer $GithubToken"
            "Accept" = "application/vnd.github.v3.diff"
            "X-GitHub-Api-Version" = "2022-11-28"
        } -Method Get
        
        return $response.Content
    }
    catch {
        Write-Warning "Error fetching PR diff: $_"
        return ""
    }
}

function Get-PRComments {
    param([int]$PRNum)
    
    $allComments = @()
    $page = 1
    
    try {
        while ($true) {
            $response = Invoke-WebRequest -Uri "$baseUrl/issues/$PRNum/comments?per_page=100&page=$page" -Headers $headers -Method Get
            $comments = $response.Content | ConvertFrom-Json
            
            if ($comments.Count -eq 0) { break }
            
            $allComments += $comments
            
            $linkHeader = $response.Headers["Link"]
            if (-not $linkHeader -or $linkHeader -notmatch 'rel="next"') { break }
            
            $page++
        }
    }
    catch {
        Write-Warning "Error fetching comments: $_"
    }
    
    return $allComments
}

function Get-PRCommits {
    param([int]$PRNum)
    
    $allCommits = @()
    $page = 1
    
    try {
        while ($true) {
            $response = Invoke-WebRequest -Uri "$baseUrl/pulls/$PRNum/commits?per_page=100&page=$page" -Headers $headers -Method Get
            $commits = $response.Content | ConvertFrom-Json
            
            if ($commits.Count -eq 0) { break }
            
            $allCommits += $commits
            
            $linkHeader = $response.Headers["Link"]
            if (-not $linkHeader -or $linkHeader -notmatch 'rel="next"') { break }
            
            $page++
        }
    }
    catch {
        Write-Warning "Error fetching commits: $_"
    }
    
    return $allCommits
}

function Get-PRFiles {
    param([int]$PRNum)
    
    $allFiles = @()
    $page = 1
    
    try {
        while ($true) {
            $response = Invoke-WebRequest -Uri "$baseUrl/pulls/$PRNum/files?per_page=100&page=$page" -Headers $headers -Method Get
            $files = $response.Content | ConvertFrom-Json
            
            if ($files.Count -eq 0) { break }
            
            $allFiles += $files
            
            $linkHeader = $response.Headers["Link"]
            if (-not $linkHeader -or $linkHeader -notmatch 'rel="next"') { break }
            
            $page++
        }
    }
    catch {
        Write-Warning "Error fetching files: $_"
    }
    
    return $allFiles
}

function Invoke-SupervisorReview {
    param(
        [string]$Spec,
        [string]$Diff,
        [array]$Comments,
        [array]$Commits,
        [array]$Files
    )
    
    # Build comprehensive review prompt
    $reviewPrompt = @"
You are a supervisor agent reviewing Copilot's work on PR #$PRNumber in $Owner/$Repo.

Your job is to perform a multi-dimensional quality review and provide actionable feedback.

SPECIFICATION:
$Spec

PR DIFF:
$Diff

RECENT COMMENTS (last 5):
$($Comments | Select-Object -Last 5 | ForEach-Object { "- [$($_.user.login)] $($_.body)" } | Out-String)

COMMITS (last 5):
$($Commits | Select-Object -Last 5 | ForEach-Object { "- $($_.sha.Substring(0,7)): $($_.commit.message)" } | Out-String)

FILES CHANGED:
$($Files | ForEach-Object { "- $($_.filename) (+$($_.additions)/-$($_.deletions))" } | Out-String)

REVIEW DIMENSIONS:
1. Spec Compliance: Does the implementation match the specification requirements?
2. Code Quality: Is the code well-structured, maintainable, and following best practices?
3. Security: Are there any security vulnerabilities or concerns?

OUTPUT FORMAT (JSON):
{
  "overall_status": "complete|incomplete|needs_fixes|escalate",
  "spec_compliance": {
    "score": 0-100,
    "issues": ["list of issues"],
    "missing_requirements": ["list of missing items"]
  },
  "code_quality": {
    "score": 0-100,
    "issues": ["list of issues"]
  },
  "security": {
    "score": 0-100,
    "vulnerabilities": ["list of vulnerabilities"],
    "concerns": ["list of concerns"]
  },
  "recommendation": "continue|fix|escalate",
  "feedback": "Detailed feedback for Copilot",
  "escalation_reason": "If escalate, why?"
}

Provide only the JSON output, no other text.
"@

    # Create temp file for prompt
    $tempPromptFile = New-TemporaryFile
    $reviewPrompt | Out-File -FilePath $tempPromptFile.FullName -Encoding UTF8
    
    try {
        # Use Copilot CLI to perform review
        Write-Host "Invoking Copilot CLI for review..." -ForegroundColor Cyan
        
        # Run copilot with the prompt
        $reviewOutput = copilot --yolo -p "$(Get-Content $tempPromptFile.FullName -Raw)" 2>&1
        
        # Try to extract JSON from output
        $jsonMatch = $reviewOutput -match '(?s)\{.*\}'
        if ($jsonMatch) {
            $jsonText = [regex]::Match($reviewOutput, '(?s)\{.*\}').Value
            $reviewResult = $jsonText | ConvertFrom-Json
            return $reviewResult
        }
        else {
            Write-Warning "Could not parse JSON from Copilot output"
            return $null
        }
    }
    catch {
        Write-Warning "Error during review: $_"
        return $null
    }
    finally {
        Remove-Item $tempPromptFile.FullName -ErrorAction SilentlyContinue
    }
}

function Invoke-Decision {
    param([object]$ReviewResult)
    
    if (-not $ReviewResult) {
        return @{
            Action = "wait"
            Message = "Review could not be completed. Will retry."
        }
    }
    
    # Determine action based on review result
    $action = "continue"
    $message = ""
    
    switch ($ReviewResult.recommendation) {
        "continue" {
            $action = "continue"
            $message = "✅ Work looks good! " + $ReviewResult.feedback
        }
        "fix" {
            $action = "fix"
            $message = "@copilot " + $ReviewResult.feedback
        }
        "escalate" {
            $action = "escalate"
            $message = "@$EscalateToUser " + $ReviewResult.feedback + "`n`nEscalation reason: " + $ReviewResult.escalation_reason
        }
        default {
            # Check scores to make decision
            $avgScore = ($ReviewResult.spec_compliance.score + $ReviewResult.code_quality.score + $ReviewResult.security.score) / 3
            
            if ($avgScore -ge 90) {
                $action = "continue"
                $message = "✅ Review complete. All quality dimensions look good."
            }
            elseif ($avgScore -ge 70) {
                $action = "fix"
                $message = "@copilot Please address the following issues:`n" + $ReviewResult.feedback
            }
            else {
                $action = "escalate"
                $message = "@$EscalateToUser Critical issues detected that require human review.`n" + $ReviewResult.feedback
            }
        }
    }
    
    return @{
        Action = $action
        Message = $message
        ReviewResult = $ReviewResult
    }
}

function Post-PRComment {
    param(
        [int]$PRNum,
        [string]$Comment
    )
    
    try {
        $body = @{
            body = $Comment
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri "$baseUrl/issues/$PRNum/comments" -Headers $headers -Method Post -Body $body -ContentType "application/json"
        
        Write-Host "Comment posted successfully" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Error posting comment: $_"
        return $false
    }
}

function Request-FileReview {
    param(
        [int]$PRNum,
        [string]$Username,
        [array]$Files
    )
    
    try {
        # Request review from user
        $reviewers = @{
            reviewers = @($Username)
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri "$baseUrl/pulls/$PRNum/requested_reviewers" -Headers $headers -Method Post -Body $reviewers -ContentType "application/json"
        
        Write-Host "Review requested from @$Username" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Error requesting review: $_"
        return $false
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
Write-Host "  Escalate To:   @$EscalateToUser"
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
        Write-Host "*** COPILOT FINISHED - STARTING REVIEW ***" -ForegroundColor Green
        Write-Host ""
        
        # Gather all PR context
        Write-Host "Gathering PR context..." -ForegroundColor Cyan
        $diff = Get-PRDiff -PRNum $PRNumber
        $comments = Get-PRComments -PRNum $PRNumber
        $commits = Get-PRCommits -PRNum $PRNumber
        $files = Get-PRFiles -PRNum $PRNumber
        
        Write-Host "  - Diff: $($diff.Length) chars"
        Write-Host "  - Comments: $($comments.Count)"
        Write-Host "  - Commits: $($commits.Count)"
        Write-Host "  - Files: $($files.Count)"
        Write-Host ""
        
        # Perform review
        Write-Host "Performing multi-dimensional review..." -ForegroundColor Cyan
        $reviewResult = Invoke-SupervisorReview -Spec $specContent -Diff $diff -Comments $comments -Commits $commits -Files $files
        
        if ($reviewResult) {
            Write-Host "Review completed" -ForegroundColor Green
            Write-Host "  - Spec Compliance: $($reviewResult.spec_compliance.score)/100"
            Write-Host "  - Code Quality: $($reviewResult.code_quality.score)/100"
            Write-Host "  - Security: $($reviewResult.security.score)/100"
            Write-Host "  - Recommendation: $($reviewResult.recommendation)"
            Write-Host ""
            
            # Make decision
            Write-Host "Making decision..." -ForegroundColor Cyan
            $decision = Invoke-Decision -ReviewResult $reviewResult
            
            Write-Host "Decision: $($decision.Action)" -ForegroundColor Cyan
            Write-Host ""
            
            # Take action
            switch ($decision.Action) {
                "continue" {
                    Write-Host "Posting approval comment..." -ForegroundColor Green
                    Post-PRComment -PRNum $PRNumber -Comment $decision.Message
                }
                "fix" {
                    Write-Host "Posting feedback to Copilot..." -ForegroundColor Yellow
                    Post-PRComment -PRNum $PRNumber -Comment $decision.Message
                }
                "escalate" {
                    Write-Host "Escalating to human..." -ForegroundColor Red
                    Post-PRComment -PRNum $PRNumber -Comment $decision.Message
                    Request-FileReview -PRNum $PRNumber -Username $EscalateToUser -Files $files
                }
                "wait" {
                    Write-Host "Waiting for next cycle..." -ForegroundColor Gray
                }
            }
        }
        else {
            Write-Warning "Review failed, will retry on next cycle"
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
