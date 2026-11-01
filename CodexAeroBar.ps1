# Scheduler adapter around the standalone AeroProgress component.
# Only this file knows Codex settings, WPF fallback and quota/countdown roles.
Import-Module (Join-Path $PSScriptRoot 'components/AeroProgress/AeroProgress.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'components/ProgressHost/ProgressHost.psm1') -Force -ErrorAction Stop
$script:aeroChecked = $false
$script:aeroAvailable = $false
$script:aeroError = ''
$script:aeroBars = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()

function Initialize-AeroAppearance {
    param($Settings)
    $defaults = [ordered]@{
        quota = 'green'
        time = 'blue'
        finish = 0
        lighting = 0
        shimmer = 100
        speed = 100
        aero = $true
    }
    $stored = if ($Settings) { $Settings.barAppearance } else { $null }
    if ($stored) {
        foreach ($name in @($defaults.Keys)) {
            if ($stored.PSObject.Properties[$name]) {
                $defaults[$name] = $stored.$name
            }
        }
    }
    foreach ($kind in @('quota','time')) {
        if ($defaults[$kind] -notin @('green','blue','cyan','violet','amber','red') -and
            [string]$defaults[$kind] -notmatch '^#[0-9a-fA-F]{6}$') {
            $defaults[$kind] = $(if ($kind -eq 'quota') { 'green' } else { 'blue' })
        }
        if ([string]$defaults[$kind] -match '^#[0-9a-fA-F]{6}$') {
            $defaults[$kind] = ([string]$defaults[$kind]).ToUpperInvariant()
        }
    }
    foreach ($key in @('finish','lighting')) {
        if ($defaults[$key] -notin @(0,1,2)) { $defaults[$key] = 0 }
        $defaults[$key] = [int]$defaults[$key]
    }
    foreach ($key in @('shimmer','speed')) {
        try { $defaults[$key] = [int]$defaults[$key] } catch { $defaults[$key] = 100 }
    }
    $defaults['shimmer'] = [math]::Clamp($defaults['shimmer'],0,200)
    $defaults['speed'] = [math]::Clamp($defaults['speed'],25,300)
    $defaults['aero'] = ($defaults['aero'] -eq $true)
    $script:aeroAppearance = $defaults
}
Initialize-AeroAppearance $null

function Update-AeroAppearance {
    param([System.Collections.IDictionary]$Appearance)
    $script:aeroAppearance = $Appearance
    foreach ($bar in @($script:aeroBars)) {
        if ($bar.IsDisposed) {
            [void]$script:aeroBars.Remove($bar)
            continue
        }
        $bar.Tag.Color = [string]$Appearance[$bar.Tag.Kind]
        Send-AeroState $bar
    }
}


function Test-AeroRenderer {
    if ($script:aeroChecked) { return $script:aeroAvailable }
    $script:aeroChecked = $true
    if ($env:CODEX_BAR_RENDERER -eq 'wpf') {
        $script:aeroError = 'WPF fallback explicitly selected.'
        return $false
    }
    $script:aeroSdk = Join-Path $PSScriptRoot 'AeroWebView2'
    $script:aeroAsset = Join-Path $PSScriptRoot 'assets/AeroBar.html'
    $support = Test-AeroProgressSupport -SdkDirectory $script:aeroSdk -AssetPath $script:aeroAsset
    $script:aeroAvailable = [bool]$support.Available
    $script:aeroError = [string]$support.Reason
    return $script:aeroAvailable
}

function Send-AeroState {
    param([System.Windows.Forms.Control]$Bar)
    if (-not $Bar -or $Bar.IsDisposed -or $Bar.Tag.Fallback -or $Bar.Tag.Failure) { return }
    # The module queues this state if WebView2 has not finished starting.
    Set-AeroProgressViewState -View $Bar -State @{
        type='set'
        value=if ($null -eq $Bar.Tag.Percent) { 0.0 } else { [double]$Bar.Tag.Percent / 100.0 }
        color=[string]$Bar.Tag.Color
        finish=[int]$script:aeroAppearance['finish']
        lighting=[int]$script:aeroAppearance['lighting']
        shimmer=[double]$script:aeroAppearance['shimmer']/100.0
        speed=[double]$script:aeroAppearance['speed']/100.0
        aero=[bool]$script:aeroAppearance['aero']
    }
}

# A failed renderer must not leave a permanent blank bar. The view itself
# stays as the stable caller reference; its fallback is a WPF ElementHost.
function Ensure-AeroFallback {
    param([System.Windows.Forms.Control]$Bar)
    if (-not $Bar -or $Bar.IsDisposed -or -not $Bar.Tag.Failure -or $Bar.Tag.Fallback) { return }
    $kind=[string]$Bar.Tag.Kind
    $factory={
        param($parent,$bounds)
        return New-FlowingProgressBar $parent $bounds.X $bounds.Y $bounds.Width $bounds.Height $kind
    }.GetNewClosure()
    try {
        $replacement=Repair-ProgressHost -Primary $Bar -FallbackFactory $factory
        if($replacement){Set-FlowingProgress $replacement $Bar.Tag.Percent}
    } catch {
        $script:aeroError = "Aero recovery failed: $($_.Exception.Message)"
    }
}
function Get-AeroProgressSurface {
    param([System.Windows.Forms.Control]$Bar)
    return Get-ProgressHostSurface -Primary $Bar
}
function Remove-AeroProgressBar {
    param([System.Windows.Forms.Control]$Bar)
    if(-not $Bar){return}
    [void]$script:aeroBars.Remove($Bar)
    Remove-ProgressHost -Primary $Bar
}

function Start-AeroHealthMonitor {
    if (-not $script:aeroHealthTimer) {
        $script:aeroHealthTimer = [System.Windows.Forms.Timer]::new()
        $script:aeroHealthTimer.Interval = 900
        $script:aeroHealthTimer.Add_Tick({
            foreach ($bar in @($script:aeroBars)) {
                if ($bar.IsDisposed) {
                    [void]$script:aeroBars.Remove($bar)
                    continue
                }
                Ensure-AeroFallback $bar
            }
            if ($script:aeroBars.Count -eq 0) { $script:aeroHealthTimer.Stop() }
        })
    }
    if (-not $script:aeroHealthTimer.Enabled) { $script:aeroHealthTimer.Start() }
}

function New-AeroProgressBar {
    param(
        [System.Windows.Forms.Control]$Parent,
        [int]$X,[int]$Y,[int]$Width,[int]$Height,
        [ValidateSet('quota','time')][string]$Kind,
        [string]$Color=''
    )
    if (-not (Test-AeroRenderer)) {
        return New-FlowingProgressBar $Parent $X $Y $Width $Height $Kind
    }
    $chosen = if ($Color -and (Test-AeroProgressColor $Color)) {
        $Color
    } else { [string]$script:aeroAppearance[$Kind] }
    try {
        $view = New-AeroProgressView -Parent $Parent -X $X -Y $Y -Width $Width -Height $Height `
            -Color $chosen -AccessibleName $(if ($Kind -eq 'quota') { 'Usage remaining' } else { 'Time until scheduled run' }) `
            -SdkDirectory $script:aeroSdk -AssetPath $script:aeroAsset `
            -UserDataDirectory (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodexResumeScheduler/AeroWebView2')
        $view.Tag.Kind = $Kind
        $script:aeroBars.Add($view)
        Start-AeroHealthMonitor
        Send-AeroState $view
        return $view
    } catch {
        $script:aeroError = "Aero view failed: $($_.Exception.Message)"
        return New-FlowingProgressBar $Parent $X $Y $Width $Height $Kind
    }
}

function Set-AeroProgress {
    param([System.Windows.Forms.Control]$Bar,$Percent)
    if ($Bar -is [System.Windows.Forms.Integration.ElementHost]) {
        Set-FlowingProgress $Bar $Percent
        return
    }
    $value = if ($null -eq $Percent) { $null } else { [double][math]::Clamp([double]$Percent,0,100) }
    if ($Bar.Tag.Percent -eq $value) { return }
    $Bar.Tag.Percent = $value
    if ($Bar.Tag.Fallback) { Set-FlowingProgress $Bar.Tag.Fallback $value; return }
    Ensure-AeroFallback $Bar
    if ($Bar.Tag.Fallback) { Set-FlowingProgress $Bar.Tag.Fallback $value; return }
    Send-AeroState $Bar
}
