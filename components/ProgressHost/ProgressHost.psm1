# Generic WinForms failure recovery, layout and ownership of paired controls.
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
Add-Type -AssemblyName System.Drawing -ErrorAction Stop
# The caller supplies its own primary view, fallback factory and state updater.
function Get-ProgressHostSurface {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.Control]$Primary)
    $replacement=if($Primary.Tag){$Primary.Tag.Fallback}else{$null}
    if($replacement -and -not $replacement.IsDisposed){return $replacement}
    return $Primary
}
function Ensure-ProgressHostFallback {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.Control]$Primary,
          [Parameter(Mandatory)][scriptblock]$FallbackFactory)
    if($Primary.IsDisposed -or -not $Primary.Tag -or -not $Primary.Tag.Failure){return $null}
    if($Primary.Tag.Fallback -and -not $Primary.Tag.Fallback.IsDisposed){return $Primary.Tag.Fallback}
    $parent=$Primary.Parent
    if(-not $parent -or $parent.IsDisposed){return $null}
    $created=$null
    try {
        $created=& $FallbackFactory $parent $Primary.Bounds
        if($created -isnot [System.Windows.Forms.Control]){throw 'Fallback factory must return a WinForms Control.'}
        if($created.Parent -ne $parent){$parent.Controls.Add($created)}
        $created.Bounds=$Primary.Bounds
        $created.Visible=$Primary.Visible
        $Primary.Tag.Fallback=$created
        $Primary.Visible=$false
        $created.BringToFront()
        return $created
    } catch {
        if($created -and -not $created.IsDisposed){$created.Dispose()}
        throw
    }
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
    if($Primary.IsDisposed){return}
    $fallback=if($Primary.Tag){$Primary.Tag.Fallback}else{$null}
    if($fallback -and -not $fallback.IsDisposed){
        if($fallback.Parent){$fallback.Parent.Controls.Remove($fallback)}
        $fallback.Dispose()
    }
    if($Primary.Parent){$Primary.Parent.Controls.Remove($Primary)}
    $Primary.Dispose()
}
Export-ModuleMember -Function Get-ProgressHostSurface,Ensure-ProgressHostFallback,Set-ProgressHostLayout,Remove-ProgressHost
