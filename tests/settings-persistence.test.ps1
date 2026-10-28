$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CodexData.ps1')
function Require($Condition, $Message) { if (-not $Condition) { throw $Message } }
$folder = Join-Path ([IO.Path]::GetTempPath()) ('codex-draft-' + [guid]::NewGuid().ToString('N'))
try {
    Require ($null -eq (Read-CodexUiSettings $folder)) 'Missing settings should return null.'
    $draft = [pscustomobject]@{
        sessionId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; repo = 'C:\repo\worktree'
        model = 'gpt-test'; effort = 'max'; access = 'yolo'; message = 'Continue the work.'
        autoResume = $false; runAt = '2027-05-02T19:27:00'
    }
    Write-CodexUiSettings $folder ([pscustomobject]@{version=1;lastAccess='yolo';draft=$draft})
    $read = Read-CodexUiSettings $folder
    foreach ($key in @('sessionId','repo','model','effort','access','message','runAt')) {
        Require ($read.draft.$key -ceq $draft.$key) "Draft field $key did not round trip."
    }
    Require ($read.draft.autoResume -eq $false) 'Unchecked auto-resume must persist.'
    Require ($read.lastAccess -eq 'yolo') 'Legacy lastAccess should be retained for migration.'
    $draft.message = ''
    $draft.access = 'read-only'
    Write-CodexUiSettings $folder ([pscustomobject]@{version=1;lastAccess='read-only';draft=$draft})
    $read = Read-CodexUiSettings $folder
    Require ($read.draft.message -ceq '') 'Empty instruction must be preserved, not defaulted.'
    Require ($read.draft.access -eq 'read-only') 'New preference should overwrite old.'
    $now = [datetime]::ParseExact('2027-05-02T18:00:00','yyyy-MM-ddTHH:mm:ss',[Globalization.CultureInfo]::InvariantCulture)
    Require ((Get-RestoredRunTime '2027-05-02T19:27:00' $now) -eq [datetime]'2027-05-02T19:27:00') 'Future local time must restore.'
    Require ($null -eq (Get-RestoredRunTime '2027-05-01T19:27:00' $now)) 'Past time must not be reused.'
    Require ($null -eq (Get-RestoredRunTime 'invalid-time' $now)) 'Invalid time must not be reused.'
    Set-Content -LiteralPath (Join-Path $folder 'settings.json') -Value '{broken'
    Require ($null -eq (Read-CodexUiSettings $folder)) 'Corrupt settings should be ignored safely.'
    Set-Content -LiteralPath (Join-Path $folder 'settings.json') -Value '{"lastAccess":"yolo"}'
    $legacy = Read-CodexUiSettings $folder
    Require ($legacy.lastAccess -eq 'yolo') 'Legacy settings should remain readable.'

    $gui = Get-Content -LiteralPath (Join-Path $root 'CodexResumeScheduler.ps1') -Raw
    foreach ($feature in @('Save-CurrentFormState','settingsTimer.Add_Tick','form.Add_FormClosing',
                           'whenBox.Add_ValueChanged','repoBox.Add_TextChanged','messageBox.Add_TextChanged',
                           'autoResumeCheck.Add_CheckedChanged','accessBox.Add_SelectedIndexChanged',
                           'effortBox.Add_SelectedIndexChanged','modelBox.Add_SelectedIndexChanged',
                           'sessionBox.Add_SelectedIndexChanged','startupSavedModelId','Get-RestoredRunTime')) {
        Require ($gui.Contains($feature)) "Missing UI persistence wiring: $feature"
    }
    Write-Host 'Draft settings roundtrip, migration, invalid/past times, and UI wiring passed.'
} finally {
    if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force }
}
