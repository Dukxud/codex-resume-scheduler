# AeroProgress — reusable WinForms/WebView2 progress component.
# No Codex, Task Scheduler, WPF or application settings dependencies.
$script:supportCache = @{}

function Test-AeroProgressColor {
    param([Parameter(Mandatory)][string]$Color)
    return ($Color -in @('green','blue','cyan','violet','amber','red') -or $Color -match '^#[0-9a-fA-F]{6}$')
}

function Test-AeroProgressSupport {
    param([Parameter(Mandatory)][string]$SdkDirectory,
          [Parameter(Mandatory)][string]$AssetPath)
    $sdk = [IO.Path]::GetFullPath($SdkDirectory)
    $asset = [IO.Path]::GetFullPath($AssetPath)
    $key = "$sdk/$asset"
    if ($script:supportCache.ContainsKey($key)) { return $script:supportCache[$key] }
    $result = [pscustomobject]@{ Available = $false; Reason = ''; AssetUri = $null }
    foreach ($file in @(
        (Join-Path $sdk 'Microsoft.Web.WebView2.Core.dll'),
        (Join-Path $sdk 'Microsoft.Web.WebView2.WinForms.dll'),
        (Join-Path $sdk 'WebView2Loader.dll'), $asset)) {
        if (-not [IO.File]::Exists($file)) {
            $result.Reason = "Missing Aero dependency: $([IO.Path]::GetFileName($file))"
            $script:supportCache[$key] = $result
            return $result
        }
    }
    try {
        # WebView2Loader.dll resolves relative to this explicitly supplied SDK.
        # This changes only the current process, never the system PATH.
        if (($env:PATH -split ';') -notcontains $sdk) { $env:PATH = "$sdk;$env:PATH" }
        Add-Type -Path (Join-Path $sdk 'Microsoft.Web.WebView2.Core.dll')
        Add-Type -Path (Join-Path $sdk 'Microsoft.Web.WebView2.WinForms.dll')
        $runtime = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::GetAvailableBrowserVersionString()
        if (-not $runtime) { throw 'Microsoft Edge WebView2 Evergreen Runtime not installed' }
        $result.AssetUri = [Uri]::new($asset)
        $result.Available = $true
    } catch { $result.Reason = $_.Exception.Message }
    $script:supportCache[$key] = $result
    return $result
}

function New-AeroProgressView {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory)][string]$SdkDirectory,
        [Parameter(Mandatory)][string]$AssetPath,
        [Parameter(Mandatory)][string]$UserDataDirectory,
        [int]$X = 0,[int]$Y = 0,
        [ValidateRange(1,8192)][int]$Width = 400,
        [ValidateRange(1,8192)][int]$Height = 17,
        [string]$Color = 'green',
        [string]$AccessibleName = 'Progress'
    )
    if (-not (Test-AeroProgressColor $Color)) { throw "Invalid Aero color: $Color" }
    $support = Test-AeroProgressSupport -SdkDirectory $SdkDirectory -AssetPath $AssetPath
    if (-not $support.Available) { throw "Aero WebView2 unavailable: $($support.Reason)" }
    $view = [Microsoft.Web.WebView2.WinForms.WebView2]::new()
    $view.Location = [Drawing.Point]::new($X,$Y)
    $view.Size = [Drawing.Size]::new($Width,$Height)
    $view.TabStop = $false
    $view.AllowExternalDrop = $false
    $view.DefaultBackgroundColor = [Drawing.Color]::Transparent
    $view.AccessibleName = $AccessibleName
    $view.Tag = [pscustomobject]@{
        Percent = $null; Color = $Color; Kind = ''
        Ready = $false; State = $null; Failure = $null
        AllowedUri = $support.AssetUri.AbsoluteUri
    }
    $creation = [Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties]::new()
    $creation.UserDataFolder = [IO.Path]::GetFullPath($UserDataDirectory)
    $view.CreationProperties = $creation
    $view.Add_CoreWebView2InitializationCompleted({
        param($control,$eventArgs)
        if (-not $eventArgs.IsSuccess) {
            $control.Tag.Failure = $eventArgs.InitializationException.Message
            return
        }
        $settings = $control.CoreWebView2.Settings
        $settings.AreDefaultContextMenusEnabled = $false
        $settings.AreDevToolsEnabled = $false
        $settings.AreBrowserAcceleratorKeysEnabled = $false
        $settings.IsZoomControlEnabled = $false
        $allowedUri = [string]$control.Tag.AllowedUri
        $control.CoreWebView2.Add_NavigationStarting({
            param($source,$event)
            if ($event.Uri -ne $allowedUri) { $event.Cancel = $true }
        }.GetNewClosure())
        $control.CoreWebView2.Add_NewWindowRequested({
            param($source,$event)
            $event.Handled = $true
        })
        $control.CoreWebView2.Add_PermissionRequested({
            param($source,$event)
            $event.State = [Microsoft.Web.WebView2.Core.CoreWebView2PermissionState]::Deny
        })
        $control.CoreWebView2.Add_ProcessFailed({
            param($source,$event)
            if (-not $control.IsDisposed) {
                $control.Tag.Ready = $false
                $control.Tag.Failure = "WebView2 process failure: $($event.ProcessFailedKind)"
            }
        }.GetNewClosure())
    }.GetNewClosure())
    $view.Add_NavigationCompleted({
        param($control,$eventArgs)
        if ($eventArgs.IsSuccess -and -not $control.IsDisposed) {
            $control.Tag.Ready = $true
            if ($null -ne $control.Tag.State) {
                $control.CoreWebView2.PostWebMessageAsJson(
                    ($control.Tag.State | ConvertTo-Json -Compress -Depth 4))
            }
        } elseif (-not $eventArgs.IsSuccess) {
            $control.Tag.Failure = "Navigation failed: $($eventArgs.WebErrorStatus)"
        }
    })
    $Parent.Controls.Add($view)
    $view.Source = $support.AssetUri
    return $view
}

function Set-AeroProgressViewState {
    param([Parameter(Mandatory)][System.Windows.Forms.Control]$View,
          [Parameter(Mandatory)][System.Collections.IDictionary]$State)
    if ($View.IsDisposed) { return }
    if ($State['type'] -cne 'set') { throw 'Invalid Aero message type' }
    $color = [string]$State['color']
    if (-not (Test-AeroProgressColor $color)) { throw 'Invalid Aero color' }
    $value = [double]$State['value']
    if (-not [double]::IsFinite($value) -or $value -lt 0 -or $value -gt 1) { throw 'Progress out of range' }
    foreach ($k in @('finish','lighting')) {
        if ([int]$State[$k] -notin @(0,1,2)) { throw "Invalid Aero $k" }
    }
    $shimmer = [double]$State['shimmer']
    $speed = [double]$State['speed']
    if (-not [double]::IsFinite($shimmer) -or $shimmer -lt 0 -or $shimmer -gt 2) { throw 'Invalid shimmer' }
    if (-not [double]::IsFinite($speed) -or $speed -lt .25 -or $speed -gt 3) { throw 'Invalid speed' }
    $snapshot = [ordered]@{
        type='set';value=$value;color=$color
        finish=[int]$State['finish'];lighting=[int]$State['lighting']
        shimmer=$shimmer;speed=$speed;aero=[bool]$State['aero']
    }
    $View.Tag.State = $snapshot
    $View.Tag.Color = $color
    if ($View.Tag.Ready -and $null -ne $View.CoreWebView2) {
        $View.CoreWebView2.PostWebMessageAsJson(($snapshot | ConvertTo-Json -Compress -Depth 4))
    }
}

Export-ModuleMember -Function Test-AeroProgressColor,Test-AeroProgressSupport,New-AeroProgressView,Set-AeroProgressViewState
