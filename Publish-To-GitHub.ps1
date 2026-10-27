# Creates the user's public GitHub repository from the extracted project files.
# Requires GitHub CLI (gh) already installed and authenticated. Never overwrites an existing repo.
$ErrorActionPreference = 'Stop'
Write-Host 'PUBLISH | PUBLIC CODEX RESUME SCHEDULER — BLACK-PUDDLE' -ForegroundColor Magenta
$root = $PSScriptRoot
$repository = 'Dukxud/codex-resume-scheduler'
if (-not (Get-Command gh.exe -ErrorAction SilentlyContinue)) { throw 'GitHub CLI is required. Install it with: winget install --id GitHub.cli -e; then run: gh auth login' }
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { throw 'Git is required.' }
& gh auth status | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI is not authenticated. Run: gh auth login' }
$expectedOwner = 'Dukxud'
$actualOwner = (& gh api user --jq '.login').Trim()
if ($LASTEXITCODE -ne 0 -or $actualOwner -cne $expectedOwner) { throw "Expected authenticated GitHub user '$expectedOwner', found '$actualOwner'. Refusing publication." }
& gh repo view $repository --json name 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { throw "Repository $repository already exists. No files were uploaded." }
Set-Location -LiteralPath $root
if (Test-Path -LiteralPath (Join-Path $root '.git')) { throw 'This folder is already a Git repository. Review it before publishing manually.' }
& git init -b main
if ($LASTEXITCODE -ne 0) { throw 'git init failed.' }
& git add -- .
if ($LASTEXITCODE -ne 0) { throw 'git add failed.' }
# Use the account's GitHub no-reply address, not the machine's personal Git email.
& git -c 'user.name=Dukxud' -c 'user.email=89496382+Dukxud@users.noreply.github.com' commit -m 'Initial public release: Codex Resume Scheduler v1.3'
if ($LASTEXITCODE -ne 0) { throw 'git commit failed; check Git output before retrying.' }
& gh repo create $repository --public --description 'Windows GUI for scheduling Codex CLI conversation continuations after usage resets.' --source . --remote origin --push
if ($LASTEXITCODE -ne 0) { throw 'GitHub publication failed. Inspect the folder/repository before retrying; no automatic retries.' }
# Creation can succeed even when a push fails. Verify the remote branch and visibility.
$publishedVisibility = (& gh repo view $repository --json visibility --jq '.visibility').Trim()
if ($LASTEXITCODE -ne 0 -or $publishedVisibility -cne 'PUBLIC') { throw 'Repository visibility was not verified as PUBLIC.' }
$localSha = (& git rev-parse HEAD).Trim()
$remoteSha = (& git ls-remote origin refs/heads/main | Select-Object -First 1) -split '\s+' | Select-Object -First 1
if ($LASTEXITCODE -ne 0 -or $remoteSha -ne $localSha) { throw 'Remote main does not match the intended local commit.' }
Write-Host "PUBLICATION VERIFIED: https://github.com/$repository" -ForegroundColor Green
