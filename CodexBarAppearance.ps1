# In-app appearance dialog for the approved Windows v1.8 + Aero v3 bars.
# Controls change only local presentation; scheduler progress values are untouched.

function Show-AeroAppearanceDialog {
    param([System.Windows.Forms.Form]$Owner)

    $dialog = [System.Windows.Forms.Form]::new()
    $dialog.Text = 'Customize progress bars'
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dialog.ClientSize = [System.Drawing.Size]::new(460,420)
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(247,250,254)
    $dialog.Font = [System.Drawing.Font]::new('Segoe UI',10)

    function Add-DialogLabel([string]$title,[int]$y) {
        $label = [System.Windows.Forms.Label]::new()
        $label.Text = $title
        $label.Location = [System.Drawing.Point]::new(19,$y + 4)
        $label.Size = [System.Drawing.Size]::new(150,25)
        $dialog.Controls.Add($label)
    }
    function Add-DialogSelect([string]$title,[int]$y,[string[]]$options,[int]$index) {
        Add-DialogLabel $title $y
        $combo = [System.Windows.Forms.ComboBox]::new()
        $combo.DropDownStyle = 'DropDownList'
        $combo.Location = [System.Drawing.Point]::new(178,$y)
        $combo.Size = [System.Drawing.Size]::new(263,30)
        [void]$combo.Items.AddRange([object[]]$options)
        $combo.SelectedIndex = $index
        $dialog.Controls.Add($combo)
        return $combo
    }
    function Add-DialogSlider([string]$title,[int]$y,[int]$min,[int]$max,[int]$current) {
        Add-DialogLabel $title $y
        $slider = [System.Windows.Forms.TrackBar]::new()
        $slider.Minimum = $min
        $slider.Maximum = $max
        $slider.Value = [math]::Clamp($current,$min,$max)
        $slider.TickFrequency = 25
        $slider.Location = [System.Drawing.Point]::new(173,$y - 1)
        $slider.Size = [System.Drawing.Size]::new(210,40)
        $dialog.Controls.Add($slider)
        $readout = [System.Windows.Forms.Label]::new()
        $readout.Location = [System.Drawing.Point]::new(392,$y + 3)
        $readout.Size = [System.Drawing.Size]::new(49,25)
        $readout.TextAlign = 'MiddleRight'
        $readout.Text = "$($slider.Value)%"
        $dialog.Controls.Add($readout)
        $slider.Add_ValueChanged({ $readout.Text = "$($slider.Value)%" }.GetNewClosure())
        return $slider
    }

    $keys = @('green','blue','cyan','violet','amber','red')
    $names = @('Windows green','Aero sapphire','Cyan','Violet','Amber','Ruby red')
    $quota = Add-DialogSelect 'Usage-bar color' 17 $names ([array]::IndexOf($keys,[string]$script:aeroAppearance['quota']))
    $time = Add-DialogSelect 'Countdown color' 61 $names ([array]::IndexOf($keys,[string]$script:aeroAppearance['time']))
    $material = Add-DialogSelect 'Liquid material' 105 @('Optical glass','Mirror enamel','Iridescent pearl') ([int]$script:aeroAppearance['finish'])
    $lighting = Add-DialogSelect 'Reflections / studio' 149 @('Product studio','Aero daylight','Neon showroom') ([int]$script:aeroAppearance['lighting'])
    $shimmer = Add-DialogSlider 'Shimmer intensity' 196 0 200 ([int]$script:aeroAppearance['shimmer'])
    $speed = Add-DialogSlider 'Shimmer speed' 246 25 300 ([int]$script:aeroAppearance['speed'])

    $enabled = [System.Windows.Forms.CheckBox]::new()
    $enabled.Text = 'Enable Aero Liquid over the original Windows bar'
    $enabled.AutoSize = $true
    $enabled.Checked = [bool]$script:aeroAppearance['aero']
    $enabled.Location = [System.Drawing.Point]::new(20,296)
    $dialog.Controls.Add($enabled)

    $note = [System.Windows.Forms.Label]::new()
    $note.Text = 'Appearance is saved locally and applied to all visible bars.'
    $note.ForeColor = [System.Drawing.Color]::DimGray
    $note.Location = [System.Drawing.Point]::new(20,326)
    $note.Size = [System.Drawing.Size]::new(421,26)
    $dialog.Controls.Add($note)

    $reset = [System.Windows.Forms.Button]::new()
    $reset.Text = 'Defaults'
    $reset.Location = [System.Drawing.Point]::new(19,373)
    $reset.Size = [System.Drawing.Size]::new(92,31)
    $reset.Add_Click({
        $quota.SelectedIndex = 0; $time.SelectedIndex = 1
        $material.SelectedIndex = 0; $lighting.SelectedIndex = 0
        $shimmer.Value = 100; $speed.Value = 100
        $enabled.Checked = $true
    }.GetNewClosure())
    $dialog.Controls.Add($reset)

    $cancel = [System.Windows.Forms.Button]::new()
    $cancel.Text = 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(241,373)
    $cancel.Size = [System.Drawing.Size]::new(95,31)
    $dialog.Controls.Add($cancel)

    $save = [System.Windows.Forms.Button]::new()
    $save.Text = 'Save and close'
    $save.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $save.Location = [System.Drawing.Point]::new(343,373)
    $save.Size = [System.Drawing.Size]::new(100,31)
    $dialog.Controls.Add($save)
    $dialog.AcceptButton = $save
    $dialog.CancelButton = $cancel

    try {
        if ($dialog.ShowDialog($Owner) -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $selection = [ordered]@{
            quota = [string]$keys[$quota.SelectedIndex]
            time = [string]$keys[$time.SelectedIndex]
            finish = [int]$material.SelectedIndex
            lighting = [int]$lighting.SelectedIndex
            shimmer = [int]$shimmer.Value
            speed = [int]$speed.Value
            aero = [bool]$enabled.Checked
        }
        Update-AeroAppearance $selection
        Queue-FormStateSave
    } finally {
        $dialog.Dispose()
    }
}
