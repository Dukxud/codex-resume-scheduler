# Pin generated Flutter Windows runners to our source-controlled native icon.
# Safe: no Codex invocation or Task Scheduler changes.
[CmdletBinding()]
param([switch]$VerifyOnly)
$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'assets/continuum_icon.ico'
$runner = Join-Path $PSScriptRoot 'windows/runner'
$rcPath = Join-Path $runner 'Runner.rc'
$cppPath = Join-Path $runner 'main.cpp'
$target = Join-Path $runner 'resources/app_icon.ico'
$expected = '1098CDBCDD8B89E5B6E657676B3881CFE2D22C2D5F19114AC1B27ACBF9D5FD56'

if (!(Test-Path -LiteralPath $source -PathType Leaf) -or
    (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne $expected) {
    throw 'Source-controlled Continuum icon is missing or changed.'
}
foreach ($file in @($rcPath, $cppPath)) {
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Flutter Windows runner missing: $file. Generate with flutter create first."
    }
}
$rc = Get-Content -LiteralPath $rcPath -Raw
if (!$rc.Contains('IDI_APP_ICON') -or !$rc.Contains('resources\\app_icon.ico')) {
    throw 'Generated Runner.rc does not bind IDI_APP_ICON to app_icon.ico.'
}
$marker = 'CONTINUUM_NATIVE_WINDOW_ICON'
$cpp = Get-Content -LiteralPath $cppPath -Raw
if (-not $VerifyOnly) {
    Copy-Item -LiteralPath $source -Destination $target -Force
    if (-not $cpp.Contains($marker)) {
        $include = '#include "utils.h"'
        $anchor = '  window.SetQuitOnClose(true);'
        if (-not $cpp.Contains($include) -or -not $cpp.Contains($anchor) -or
            $cpp.Contains('WM_SETICON')) {
            throw 'Unsupported Flutter main.cpp template; refusing blind patch.'
        }
        $cpp = $cpp.Replace($include, $include + [Environment]::NewLine + '#include "resource.h"')
        $addition = @'
  // CONTINUUM_NATIVE_WINDOW_ICON: pin the small HWND icon independently of
  // Windows class-icon fallback. Large icon comes from the same PE resource.
  auto continuumIcon = reinterpret_cast<HICON>(::LoadImageW(
      instance, MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      ::GetSystemMetrics(SM_CXSMICON), ::GetSystemMetrics(SM_CYSMICON),
      LR_SHARED));
  if (!continuumIcon) {
    return EXIT_FAILURE;
  }
  ::SendMessageW(window.GetHandle(), WM_SETICON, ICON_SMALL,
                 reinterpret_cast<LPARAM>(continuumIcon));

'@
        $cpp = $cpp.Replace($anchor, $addition + $anchor)
        [IO.File]::WriteAllText($cppPath, $cpp, [Text.UTF8Encoding]::new($false))
    }
}
$actual = Get-Content -LiteralPath $cppPath -Raw
if (!(Test-Path -LiteralPath $target -PathType Leaf) -or
    (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -cne $expected -or
    -not $actual.Contains($marker) -or
    -not $actual.Contains('#include "resource.h"') -or
    -not $actual.Contains('WM_SETICON, ICON_SMALL')) {
    throw 'Native runner icon was not applied consistently.'
}
Write-Host 'CONTINUUM WIN32 ICON PASS - resource and HWND both pinned.' -ForegroundColor Green
