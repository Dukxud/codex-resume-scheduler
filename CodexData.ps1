# Codex Resume Scheduler - local data readers (PowerShell 7).
# Used by the GUI's short-lived background thread jobs and scheduled runners.
# No UI controls, timers, or persistent services.

function Get-RepositoryRoot {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return $null }
    try {
        $result = & git -C $Path rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $result) { return $null }
        return ([string]($result | Select-Object -First 1)).Trim()
    } catch { return $null }
}

function Get-RecentCliSessions {
    $sessionRoot = Join-Path $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }) 'sessions'
    $sessions = @()
    if (Test-Path -LiteralPath $sessionRoot -PathType Container) {
        $rollouts = @(Get-ChildItem -LiteralPath $sessionRoot -File -Recurse -Filter 'rollout-*.jsonl' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($item in $rollouts) {
            try {
                $line = Get-Content -LiteralPath $item.FullName -TotalCount 1 -ErrorAction Stop
                $meta = ($line | ConvertFrom-Json).payload
                if ($meta.source -ne 'cli' -or $meta.id -notmatch $sessionIdPattern) { continue }
                if (-not $seen.Add([string]$meta.id)) { continue }
                $name = if ($meta.cwd) { Split-Path -Leaf ([string]$meta.cwd) } else { 'CLI session' }
                $sessions += [pscustomobject]@{
                    Id = [string]$meta.id
                    Cwd = [string]$meta.cwd
                    File = [string]$item.FullName
                    Display = ('{0} | {1:MM/dd HH:mm} | {2}' -f $name,$item.LastWriteTime,$meta.id)
                }
                if ($sessions.Count -ge 30) { break }
            } catch { continue }
        }
    }
    return $sessions
}

function Find-SessionRepository {
    param($Session)
    if (-not $Session) { return $null }
    $candidates = [System.Collections.Generic.List[string]]::new()
    $direct = Get-RepositoryRoot ([string]$Session.Cwd)
    if ($direct) { $candidates.Add($direct) }

    # A prior schedule is evidence, not proof that it targeted the right checkout.
    if (Test-Path -LiteralPath $appDir -PathType Container) {
        foreach ($saved in @(Get-ChildItem -LiteralPath $appDir -Filter 'CodexResume-*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5)) {
            try {
                $job = Get-Content -LiteralPath $saved.FullName -Raw -ErrorAction Stop | ConvertFrom-Json
                if ([string]$job.sessionId -ne [string]$Session.Id) { continue }
                $root = Get-RepositoryRoot ([string]$job.repo)
                if ($root -and $root.TrimEnd([char[]]@('/','\')) -ieq ([string]$job.repo).TrimEnd([char[]]@('/','\'))) {
                    $candidates.Add($root)
                }
            } catch { continue }
        }
    }

    # Use only structured cwd/workdir fields belonging to this session.
    # CLI sessions can move from their starting repository to an isolated worktree.
    if (Test-Path -LiteralPath $Session.File -PathType Leaf) {
        $contexts = [System.Collections.Generic.List[string]]::new()
        $toolDirs = [System.Collections.Generic.List[string]]::new()
        try {
            foreach ($line in @(Get-Content -LiteralPath $Session.File -Tail 800 -ErrorAction Stop)) {
                if ($line -notmatch '"(?:cwd|workdir|arguments)"') { continue }
                try {
                    $record = $line | ConvertFrom-Json -ErrorAction Stop
                    if ($record.type -eq 'turn_context' -and -not [string]::IsNullOrWhiteSpace([string]$record.payload.cwd)) {
                        $contexts.Add([string]$record.payload.cwd)
                    } elseif ($record.type -eq 'response_item' -and $record.payload.type -eq 'function_call' -and $record.payload.arguments) {
                        $arguments = $record.payload.arguments | ConvertFrom-Json -ErrorAction Stop
                        if ($arguments.workdir -is [string] -and $arguments.workdir) { $toolDirs.Add([string]$arguments.workdir) }
                    }
                } catch { continue }
            }
            foreach ($directory in @($contexts.ToArray() | Select-Object -Last 8) + @($toolDirs.ToArray() | Select-Object -Last 12)) {
                $root = Get-RepositoryRoot $directory
                if ($root) { $candidates.Add($root) }
            }
        } catch {
            # Preserve other evidence, but never infer a root from malformed rollout text.
        }
    }

    $roots = @($candidates.ToArray() | Sort-Object -Unique)
    if ($roots.Count -eq 1) { return [pscustomobject]@{ Root = $roots[0]; Source = 'consistent session repository evidence'; Candidates = $roots } }
    if ($roots.Count -gt 1) { return [pscustomobject]@{ Root = $null; Source = 'conflicting worktrees'; Candidates = $roots } }
    return $null
}

function Get-UpcomingCodexTasks {
    $items = @()
    # Query our task prefixes rather than enumerate every Windows scheduled task.
    $tasks = @(Get-ScheduledTask -TaskName 'CodexResume-*' -ErrorAction SilentlyContinue) +
             @(Get-ScheduledTask -TaskName 'BP*-Codex-*' -ErrorAction SilentlyContinue)
    foreach ($task in $tasks) {
        if ($task.TaskName -notmatch '^(CodexResume-|BP\d+-Codex-(?:Resume|Test)$)') { continue }
        if ($task.State -eq 'Disabled' -or $task.State -eq 'Running') { continue }
        $trig = @($task.Triggers | Where-Object { $_.StartBoundary }) | Select-Object -First 1
        if (-not $trig) { continue }
        try { $when = [datetime]$trig.StartBoundary } catch { continue }
        if ($when -le (Get-Date)) { continue }
        $name = [string]$task.TaskName
        $json = Join-Path $appDir ($name + '.json')
        $description = 'Existing scheduled task'
        $session = '-'
        $repo = '-'
        if (Test-Path -LiteralPath $json) {
            try {
                $job = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
                $description = "$($job.model) / $($job.effort) | $($job.access) | $($job.message)"
                $session = [string]$job.sessionId
                $repo = [string]$job.repo
            } catch { $description = 'Scheduled task (job data unreadable)' }
        } elseif ($name -match '^BP\d+-Codex-') {
            # Surface existing BPxx tasks without modifying their definitions.
            $repo = [string]$task.Actions[0].WorkingDirectory
            $match = [regex]::Match([string]$task.Actions[0].Arguments, '-File\s+"([^"]+)"')
            if ($match.Success -and (Test-Path -LiteralPath $match.Groups[1].Value -PathType Leaf)) {
                try {
                    $legacy = Get-Content -LiteralPath $match.Groups[1].Value -Raw
                    $sidMatch = [regex]::Match($legacy, 'resume\s+"([0-9a-fA-F-]{36})"')
                    if ($sidMatch.Success) { $session = $sidMatch.Groups[1].Value }
                    $effortMatch = [regex]::Match($legacy, 'model_reasoning_effort=(medium|high|xhigh)')
                    $effortName = if ($effortMatch.Success) { $effortMatch.Groups[1].Value } else { 'unspecified' }
                    $accessName = if ($legacy.Contains('--dangerously-bypass-approvals-and-sandbox')) { 'YOLO' } elseif ($legacy.Contains('--sandbox read-only')) { 'read-only' } else { 'other' }
                    $description = "$effortName | $accessName | existing BP task"
                } catch { }
            }
        }
        $items += [pscustomobject]@{ Name = $name; When = $when; Repo = $repo; Session = $session; Description = $description }
    }
    return ($items | Sort-Object When)
}

function Read-SessionModel {
    param($Session)
    if (-not $Session -or -not (Test-Path -LiteralPath $Session.File -PathType Leaf)) { return $null }
    try {
        foreach ($line in @(Get-Content -LiteralPath $Session.File -Tail 600) | Select-Object -Last 600) {
            if ($line -notmatch '"model"') { continue }
            $record = $line | ConvertFrom-Json -ErrorAction Stop
            if ($record.type -eq 'turn_context' -and $record.payload.model -is [string]) { $found = [string]$record.payload.model }
        }
        return $found
    } catch { return $null }
}
