# Live WebGL2 renderer from the assembled reusable kit, with no Codex adapter.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$root=Split-Path -Parent $PSScriptRoot
$temp=Join-Path ([IO.Path]::GetTempPath()) ('standalone-aero-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -Path $temp -ItemType Directory -Force)
$form=$null
try {
    $archives=Join-Path $temp 'archives'
    $archive=& (Join-Path $root 'scripts/Package-ReusableComponents.ps1') -OutputDirectory $archives -Preview | Where-Object {$_ -is [string] -and $_.EndsWith('.zip')} | Select-Object -Last 1
    if(-not $archive -or -not (Test-Path -LiteralPath $archive)){throw 'Reusable kit build failed.'}
    $expanded=Join-Path $temp 'consumer'
    Expand-Archive -LiteralPath $archive -DestinationPath $expanded
    $kit=Get-ChildItem -LiteralPath $expanded -Directory | Select-Object -First 1
    $module=Join-Path $kit.FullName 'components/AeroProgress'
    if(Test-Path (Join-Path $kit.FullName 'CodexRunEngine.ps1')){throw 'Reusable kit contained application worker.'}
    Import-Module (Join-Path $module 'AeroProgress.psd1') -Force -ErrorAction Stop
    $sdk=Join-Path $module 'AeroWebView2'
    $asset=Join-Path $module 'AeroBar.html'
    $oldPath=$env:PATH
    $support=Test-AeroProgressSupport -SdkDirectory $sdk -AssetPath $asset
    if(-not $support.Available){throw "Packaged Aero module unavailable: $($support.Reason)"}
    if($env:PATH -cne $oldPath){throw 'Reusable WebView2 module modified PATH.'}
    # A transient missing dependency must be retried after it is repaired.
    $missingAsset=Join-Path $temp 'previously-missing.html'
    $unavailable=Test-AeroProgressSupport -SdkDirectory $sdk -AssetPath $missingAsset
    if($unavailable.Available){throw 'Absent renderer asset was accepted.'}
    Copy-Item -LiteralPath $asset -Destination $missingAsset
    $repaired=Test-AeroProgressSupport -SdkDirectory $sdk -AssetPath $missingAsset
    if(-not $repaired.Available){throw 'Missing-asset failure remained cached after repair.'}
    $form=[System.Windows.Forms.Form]::new()
    $form.ClientSize=[System.Drawing.Size]::new(460,110)
    $view=New-AeroProgressView -Parent $form -SdkDirectory $sdk -AssetPath $asset -UserDataDirectory (Join-Path $temp 'webdata') -X 15 -Y 30 -Width 400 -Height 17 -Color 'violet' -AccessibleName 'Standalone second application'
    # An unrelated host owns Tag without interfering with private Aero state.
    $view.Tag = [pscustomobject]@{ Owner='UnrelatedDesktopApp'; Ticket=19 }
    Set-AeroProgressViewState -View $view -State @{type='set';value=.37;color='violet';finish=1;lighting=1;shimmer=1.2;speed=1.0;aero=$true}
    if ($view.Tag.Owner -ne 'UnrelatedDesktopApp' -or $view.Tag.Ticket -ne 19) { throw 'AeroProgress overwrote consumer-owned Control.Tag.' }
    $initialStatus=Get-AeroProgressViewStatus -View $view
    if ([math]::Abs($initialStatus.Value-.37) -gt .001) { throw 'Aero status did not retain its own progress value.' }
    $form.Show()
    $deadline=(Get-Date).AddSeconds(25)
    while(-not (Get-AeroProgressViewStatus -View $view).Ready -and (Get-Date) -lt $deadline){
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 40
    }
    if(-not (Get-AeroProgressViewStatus -View $view).Ready){throw "Standalone WebView2 navigation failed: $((Get-AeroProgressViewStatus -View $view).Failure)"}
    $proof=$null
    while(-not $proof -and (Get-Date) -lt $deadline){
        [System.Windows.Forms.Application]::DoEvents()
        $script=$view.CoreWebView2.ExecuteScriptAsync('JSON.stringify({engine:window.aeroBarProof?.getEngine(),target:window.aeroBarProof?.getTarget(),color:window.aeroBarProof?.getColor()})')
        while(-not $script.IsCompleted -and (Get-Date) -lt $deadline){
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 40
        }
        if($script.IsCompleted -and -not $script.IsFaulted){
            try {$proof=($script.Result | ConvertFrom-Json) | ConvertFrom-Json} catch {}
        }
        if(-not $proof){Start-Sleep -Milliseconds 60}
    }
    if(-not $proof -or $proof.engine -ne 'webgl2' -or $proof.color -ne 'violet' -or [math]::Abs([double]$proof.target-.37) -gt .001){
        throw "Independent shader did not reflect state: $($proof | ConvertTo-Json -Compress)"
    }
    if($env:PATH -cne $oldPath){throw 'Rendering changed process-wide PATH.'}
    Write-Host 'Independent packaged AeroProgress: WebGL2 animation, preset, percentage, recovery and environment isolation PASS.'
}finally{
    if($form){$form.Close();$form.Dispose()}
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
}
