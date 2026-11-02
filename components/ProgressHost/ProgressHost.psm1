# Generic Windows Forms primary/fallback control ownership.
# Failure state and the caller's Control.Tag belong to the caller, not this module.
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
Add-Type -AssemblyName System.Drawing -ErrorAction Stop
$script:fallbacks=[System.Runtime.CompilerServices.ConditionalWeakTable[System.Windows.Forms.Control,System.Windows.Forms.Control]]::new()

function Get-ProgressHostSurface {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.Control]$Primary)
    if($Primary.IsDisposed){return $Primary}
    $fallback=[System.Windows.Forms.Control]$null
    if($script:fallbacks.TryGetValue($Primary,[ref]$fallback) -and $fallback -and -not $fallback.IsDisposed){
        return $fallback
    }
    return $Primary
}
function Repair-ProgressHost {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.Control]$Primary,
          [Parameter(Mandatory)][bool]$Failed,
          [Parameter(Mandatory)][scriptblock]$FallbackFactory)
    if($Primary.IsDisposed -or -not $Failed){return $null}
    $active=Get-ProgressHostSurface -Primary $Primary
    if($active -ne $Primary){return $active}
    $parent=$Primary.Parent
    if(-not $parent -or $parent.IsDisposed){return $null}
    $created=$null
    try {
        $created=& $FallbackFactory $parent $Primary.Bounds
        if($created -isnot [System.Windows.Forms.Control]){throw 'Fallback factory must return a WinForms Control.'}
        if($created.IsDisposed){throw 'Fallback factory returned a disposed control.'}
        if($created.Parent -ne $parent){$parent.Controls.Add($created)}
        $created.Bounds=$Primary.Bounds
        $created.Visible=$Primary.Visible
        [void]$script:fallbacks.Remove($Primary)
        $script:fallbacks.Add($Primary,$created)
        $Primary.Visible=$false
        $created.BringToFront()
        return $created
    } catch {
        if($created -and -not $created.IsDisposed){
            if($created.Parent){$created.Parent.Controls.Remove($created)}
            $created.Dispose()
        }
        throw
    }
}
function Reset-ProgressHostFallback {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.Control]$Primary)
    $fallback=Get-ProgressHostSurface -Primary $Primary
    if($fallback -eq $Primary){return}
    $visible=$fallback.Visible
    [void]$script:fallbacks.Remove($Primary)
    if($fallback.Parent){$fallback.Parent.Controls.Remove($fallback)}
    $fallback.Dispose()
    if(-not $Primary.IsDisposed){$Primary.Visible=$visible}
}
function Set-ProgressHostLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.Control]$Primary,
          [Parameter(Mandatory)][System.Drawing.Rectangle]$Bounds,
          [Parameter(Mandatory)][bool]$Visible)
    if($Primary.IsDisposed){return}
    $surface=Get-ProgressHostSurface -Primary $Primary
    if($surface.IsDisposed){return}
    $surface.Bounds=$Bounds
    $surface.Visible=$Visible
    if($surface -ne $Primary){$Primary.Visible=$false}
}
function Remove-ProgressHost {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.Control]$Primary)
    Reset-ProgressHostFallback -Primary $Primary
    if($Primary.Parent){$Primary.Parent.Controls.Remove($Primary)}
    if(-not $Primary.IsDisposed){$Primary.Dispose()}
}
Export-ModuleMember -Function Get-ProgressHostSurface,Repair-ProgressHost,Reset-ProgressHostFallback,Set-ProgressHostLayout,Remove-ProgressHost
