# The owner-approved v1.8 Windows + Aero Liquid v3 hybrid.
# Hosted as a small, offline WebView2 surface; the existing WPF control remains
# the deterministic fallback when Microsoft's browser runtime is unavailable.
$script:aeroChecked = $false
$script:aeroAvailable = $false
$script:aeroError = ''

function Test-AeroRenderer {
    if ($script:aeroChecked) { return $script:aeroAvailable }
    $script:aeroChecked = $true
    if ($env:CODEX_BAR_RENDERER -eq 'wpf') {
        $script:aeroError = 'WPF fallback explicitly selected.'
        return $false
    }
    $sdk = Join-Path $PSScriptRoot 'AeroWebView2'
    $core = Join-Path $sdk 'Microsoft.Web.WebView2.Core.dll'
    $forms = Join-Path $sdk 'Microsoft.Web.WebView2.WinForms.dll'
    $loader = Join-Path $sdk 'WebView2Loader.dll'
    $page = Join-Path $PSScriptRoot 'assets\AeroBar.html'
    foreach ($item in @($core,$forms,$loader,$page)) {
        if (-not (Test-Path -LiteralPath $item -PathType Leaf)) {
            $script:aeroError = "Aero dependency missing: $([IO.Path]::GetFileName($item)). Using WPF."
            return $false
        }
    }
    try {
        # A .NET runtime dynamically loads the signed Microsoft native loader.
        $env:PATH = "$sdk;$env:PATH"
        Add-Type -Path $core
        Add-Type -Path $forms
        $version = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::GetAvailableBrowserVersionString()
        if ([string]::IsNullOrWhiteSpace($version)) { throw 'Microsoft Edge WebView2 Runtime not found.' }
        $script:aeroDocumentUri = [System.Uri]::new((Resolve-Path -LiteralPath $page).Path)
        $script:aeroAvailable = $true
    } catch {
        $script:aeroError = "Aero initialization unavailable: $($_.Exception.Message)"
    }
    return $script:aeroAvailable
}

function Send-AeroState {
    param([System.Windows.Forms.Control]$Bar)
    if (-not $Bar -or $Bar.IsDisposed -or -not $Bar.Tag.Ready -or $null -eq $Bar.CoreWebView2) { return }
    $payload = @{
        type = 'set'
        value = if ($null -eq $Bar.Tag.Percent) { 0 } else { [double]$Bar.Tag.Percent / 100 }
        color = [string]$Bar.Tag.Color
    } | ConvertTo-Json -Compress
    $Bar.CoreWebView2.PostWebMessageAsJson($payload)
}

function New-AeroProgressBar {
    param(
        [System.Windows.Forms.Control]$Parent,
        [int]$X, [int]$Y, [int]$Width, [int]$Height,
        [ValidateSet('quota','time')][string]$Kind,
        [ValidateSet('green','blue','cyan','violet','amber','red')][string]$Color = ''
    )
    if (-not (Test-AeroRenderer)) {
        return New-FlowingProgressBar $Parent $X $Y $Width $Height $Kind
    }

    $selected = if ($Color) { $Color } elseif ($Kind -eq 'quota') { 'green' } else { 'blue' }
    $bar = [Microsoft.Web.WebView2.WinForms.WebView2]::new()
    $bar.Location = [System.Drawing.Point]::new($X,$Y)
    $bar.Size = [System.Drawing.Size]::new($Width,$Height)
    $bar.TabStop = $false
    $bar.AllowExternalDrop = $false
    $bar.DefaultBackgroundColor = [System.Drawing.Color]::Transparent
    $bar.AccessibleName = if ($Kind -eq 'quota') { 'Usage remaining' } else { 'Time until scheduled run' }
    $bar.Tag = [pscustomobject]@{ Percent = $null; Color = $selected; Ready = $false }
    $properties = [Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties]::new()
    $properties.UserDataFolder = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodexResumeScheduler\AeroWebView2'
    $bar.CreationProperties = $properties

    $bar.Add_CoreWebView2InitializationCompleted({
        param($sender,$eventArgs)
        Write-Host "Aero WebView2 init: success=$($eventArgs.IsSuccess)"
        if (-not $eventArgs.IsSuccess) {
            $script:aeroError = "WebView2 failed: $($eventArgs.InitializationException.Message)"
            return
        }
        $settings = $sender.CoreWebView2.Settings
        $settings.AreDefaultContextMenusEnabled = $false
        $settings.AreDevToolsEnabled = $false
        $settings.AreBrowserAcceleratorKeysEnabled = $false
        $settings.IsZoomControlEnabled = $false
        $sender.CoreWebView2.Add_NavigationStarting({
            param($source,$event)
            Write-Host "Aero navigating: $($event.Uri); expected: $($script:aeroDocumentUri.AbsoluteUri)"
            if ($event.Uri -ne $script:aeroDocumentUri.AbsoluteUri) { $event.Cancel = $true }
        })
    })
    $bar.Add_NavigationCompleted({
        param($sender,$eventArgs)
        Write-Host "Aero navigation completed: $($eventArgs.IsSuccess), $($eventArgs.WebErrorStatus)"
        if ($eventArgs.IsSuccess -and -not $sender.IsDisposed) {
            $sender.Tag.Ready = $true
            Send-AeroState $sender
        } elseif (-not $eventArgs.IsSuccess) {
            $script:aeroError = "Aero HTML navigation failed: $($eventArgs.WebErrorStatus)"
        }
    })
    $Parent.Controls.Add($bar)
    # Source assignment starts initialization asynchronously; no GUI blocking.
    $bar.Source = $script:aeroDocumentUri
    return $bar
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
    Send-AeroState $Bar
}
