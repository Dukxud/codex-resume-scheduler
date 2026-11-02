# Small, reusable Windows Forms shell primitives. No application settings or Codex.
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
Add-Type -AssemblyName System.Drawing -ErrorAction Stop
function New-DesktopWindow {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Title,
          [ValidateRange(100,6000)][int]$Width=920,
          [ValidateRange(100,6000)][int]$Height=865,
          [int]$MinimumWidth=$Width,
          [int]$MinimumHeight=$Height,
          [string]$FontName='Segoe UI',
          [ValidateRange(6,36)][float]$FontSize=10)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $form=[System.Windows.Forms.Form]::new()
    $form.Text=$Title
    $form.ClientSize=[System.Drawing.Size]::new($Width,$Height)
    $form.MinimumSize=[System.Drawing.Size]::new($MinimumWidth,$MinimumHeight)
    $form.StartPosition=[System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.BackColor=[System.Drawing.Color]::White
    $form.Font=[System.Drawing.Font]::new($FontName,$FontSize)
    $form.AutoScaleMode=[System.Windows.Forms.AutoScaleMode]::Dpi
    return $form
}
function Add-DesktopLabel {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.Control]$Parent,
          [Parameter(Mandatory)][string]$Text,
          [int]$X,[int]$Y,[int]$Width=130,[int]$Height=25)
    $label=[System.Windows.Forms.Label]::new()
    $label.Text=$Text
    $label.Location=[System.Drawing.Point]::new($X,$Y)
    $label.Size=[System.Drawing.Size]::new($Width,$Height)
    $Parent.Controls.Add($label)
    return $label
}
function Add-DesktopButton {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.Control]$Parent,
          [Parameter(Mandatory)][string]$Text,
          [int]$X,[int]$Y,[int]$Width=110,[int]$Height=31)
    $button=[System.Windows.Forms.Button]::new()
    $button.Text=$Text
    $button.Location=[System.Drawing.Point]::new($X,$Y)
    $button.Size=[System.Drawing.Size]::new($Width,$Height)
    $button.UseVisualStyleBackColor=$true
    $Parent.Controls.Add($button)
    return $button
}
Export-ModuleMember -Function New-DesktopWindow,Add-DesktopLabel,Add-DesktopButton
