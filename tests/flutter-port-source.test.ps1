# Source and boundary smoke checks without requiring Flutter on existing CI hosts.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$folder=Join-Path $root 'flutter_port'
$bridge=Join-Path $folder 'windows_bridge.ps1'
# A frontend can fail at startup because it dot-sources the backend. Parse
# the entire load chain before the costly Flutter install, not just the bridge.
foreach($relative in @(
    'flutter_port/windows_bridge.ps1','CodexRunEngine.ps1',
    'CodexQuotaContinuation.ps1','CodexTerminalRun.ps1','CodexData.ps1','CodexSessionRepository.ps1',
    'CodexRunActivity.ps1',
    'CodexResumeScheduler.ps1','components/JobOutcomes/JobOutcomes.psm1'
)){
    $file=Join-Path $root $relative
    $tokens=$null;$errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
    if(@($errors).Count){
        throw "Flutter startup dependency does not parse: $relative line $($errors[0].Extent.StartLineNumber): $($errors[0].Message)"
    }
}
foreach($relative in @('pubspec.yaml','lib/main.dart','lib/aero_bar.dart',
        'lib/bridge.dart','lib/scheduler_controller.dart','lib/dashboard_skin.dart','lib/dashboard_frame.dart',
        'lib/dashboard_workbench.dart','lib/dashboard_monitor.dart','lib/date_labels.dart','lib/desktop_window.dart',
        'lib/aero_appearance.dart','lib/appearance_dialog.dart','test/appearance_test.dart','test/widget_test.dart',
        'test/logic_test.dart','test/aero_static_test.dart','test/window_mode_test.dart','test/windows_adapter_integration_test.dart','test/parity_capture_test.dart','Build-WindowsPreview.ps1','Run-WindowsReview.ps1','Apply-WindowsIcon.ps1','assets/continuum_icon.ico','README.md')){
    if(-not (Test-Path -LiteralPath (Join-Path $folder $relative) -PathType Leaf)){throw "Missing Flutter file: $relative"}
}
foreach($relative in @('Run-WindowsReview.ps1','Build-WindowsPreview.ps1','../tests/flutter-port-bridge.test.ps1','../tests/flutter-window-icon.test.ps1','Apply-WindowsIcon.ps1')){
    $path=Join-Path $folder $relative
    $pTokens=$null;$pErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$pTokens,[ref]$pErrors)
    if(@($pErrors).Count){throw "PowerShell preview script failed parsing: $relative - $($pErrors[0].Message)"}
}
$source=Get-Content -LiteralPath $bridge -Raw
foreach($contract in @('Test-CanonicalWorkspaceIdentity','Assert-ModelEffortSupported',
    'Publish-ImmutableRuntime','Register-OneTimeTask','Remove-OneTimeTask',
    'Get-CodexRunEvidence','Get-CodexRunHistory','Get-CodexCliJs')){
    if(-not $source.Contains($contract)){throw "Flutter Windows adapter lost safety contract: $contract"}
}
if($source -match 'Register-ScheduledTask|codex exec resume|autoResume\s*='){throw 'Flutter bridge duplicated worker policy.'}

# The port must preserve the EXACT approved v1.16 optics and native pixels
# except for Flutter fragment coordinates and premultiplied alpha.
$lf=[string][char]10
$html=(Get-Content -LiteralPath (Join-Path $root 'assets/AeroBar.html') -Raw).Replace([string][char]13,'')
$match=[regex]::Match($html,'(?s)<script id="hybridfrag" type="x-shader/x-fragment">(?<code>.*?)</script>')
if(-not $match.Success){throw 'Approved Aero v3 shader missing.'}
$original=$match.Groups['code'].Value
$adapted=$original -replace '^#version 300 es\n','' -replace '^precision highp float;\n',''
$adapted=$adapted.Replace('vec2 uv=gl_FragCoord.xy/uRes.xy;', "vec2 uv=FlutterFragCoord().xy/uRes.xy;$lf    uv.y=1.-uv.y;")
$adapted=$adapted.Replace('fragColor=vec4(liquid,alpha);','fragColor=vec4(liquid*alpha,alpha);')
$expected="#version 460 core$lf#include <flutter/runtime_effect.glsl>$lf// Derived from the approved Aero v3 v2.0.1 fragment shader in assets/AeroBar.html.$lf// Only coordinate and premultiplied-alpha adaptation for Flutter are changed.$lf"+$adapted
$actual=(Get-Content -LiteralPath (Join-Path $folder 'shaders/aero_liquid.frag') -Raw).Replace([string][char]13,'')
if($actual -cne $expected){throw 'Flutter shader drifted from approved v1.16 Aero source.'}
$native=[regex]::Match($html,'(?s)<script id="native-images" type="application/json">(?<json>.*?)</script>')
if(-not $native.Success){throw 'Approved Windows sprites missing.'}
$sprites=ConvertFrom-Json -InputObject $native.Groups['json'].Value -AsHashtable
foreach($key in @('green','blue','cyan','violet','amber','red')){
    $uri=[string]$sprites[$key]
    if(-not $uri.StartsWith('data:image/png;base64,')){throw "Original sprite missing: $key"}
    $bytes=[Convert]::FromBase64String($uri.Substring('data:image/png;base64,'.Length))
    $file=Join-Path $folder "assets/native/$key.png"
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw "Flutter sprite missing: $key"}
    $actualBytes=[IO.File]::ReadAllBytes($file)
    $expectedHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    $actualHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($actualBytes))
    if($expectedHash -cne $actualHash){throw "Flutter Windows sprite differs: $key"}
}
$pubspec=Get-Content -LiteralPath (Join-Path $folder 'pubspec.yaml') -Raw
if(-not $pubspec.Contains('shaders/aero_liquid.frag') -or -not $pubspec.Contains('assets/native/')) {
    throw 'Shader or native sprites not packaged.'
}
$nativeIcon=Join-Path $folder 'assets/continuum_icon.ico'
$nativeHash=(Get-FileHash -LiteralPath $nativeIcon -Algorithm SHA256).Hash
if($nativeHash -cne '1098CDBCDD8B89E5B6E657676B3881CFE2D22C2D5F19114AC1B27ACBF9D5FD56'){
    throw 'Pinned native Continuum icon changed.'
}
$installer=Get-Content -LiteralPath (Join-Path $folder 'Apply-WindowsIcon.ps1') -Raw
if(-not $installer.Contains('WM_SETICON, ICON_SMALL') -or
   -not $installer.Contains('resources/app_icon.ico') -or
   -not $installer.Contains('VerifyOnly')){throw 'Native titlebar icon enforcement missing.'}
Write-Host 'Flutter bridge, approved Aero optics and exact Windows pixels PASS.'

