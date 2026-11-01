# Live, transactional appearance editor for the approved Windows/Aero progress bars.
# Changes render immediately in both preview and existing bars. Only Save persists.

function Show-AeroAppearanceDialog {
    param([System.Windows.Forms.Form]$Owner)

    $previous = [ordered]@{}
    foreach ($key in @('quota','time','finish','lighting','shimmer','speed','aero')) {
        $previous[$key] = $script:aeroAppearance[$key]
    }
    $draft = [ordered]@{}
    foreach ($key in $previous.Keys) { $draft[$key] = $previous[$key] }
    $presets = @('green','blue','cyan','violet','amber','red')
    $names = @('Windows green','Aero sapphire','Lagoon cyan','Amethyst','Warm amber','Ruby red','Custom color')
    $sampleHex = @('#14DE8E','#168DFF','#04D5F7','#9D64FF','#FFB328','#FF3B62')
    $custom = [ordered]@{ quota = '#32BCFF'; time = '#EF78C1' }
    foreach ($kind in @('quota','time')) {
        if ([string]$draft[$kind] -match '^#[0-9a-fA-F]{6}$') {
            $custom[$kind] = ([string]$draft[$kind]).ToUpperInvariant()
        }
    }

    $dialog = [System.Windows.Forms.Form]::new()
    $dialog.Text = 'Customize progress bars'
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dialog.ClientSize = [System.Drawing.Size]::new(566,625)
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(246,249,253)
    $dialog.Font = [System.Drawing.Font]::new('Segoe UI',10)

    function Add-Label([string]$text,[int]$x,[int]$y,[int]$width,[int]$height=24) {
        $item = [System.Windows.Forms.Label]::new()
        $item.Text = $text
        $item.Location = [System.Drawing.Point]::new($x,$y)
        $item.Size = [System.Drawing.Size]::new($width,$height)
        $dialog.Controls.Add($item)
        return $item
    }
    function Add-Select([string]$title,[int]$top,[string[]]$items,[int]$selection) {
        [void](Add-Label $title 19 ($top+5) 140 25)
        $combo = [System.Windows.Forms.ComboBox]::new()
        $combo.Name = 'Appearance' + ($title -replace '[^a-zA-Z]', '')
        $combo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $combo.Location = [System.Drawing.Point]::new(163,$top)
        $combo.Size = [System.Drawing.Size]::new(264,30)
        [void]$combo.Items.AddRange([object[]]$items)
        $combo.SelectedIndex = $selection
        $dialog.Controls.Add($combo)
        return $combo
    }
    function Add-Slider([string]$title,[int]$top,[int]$low,[int]$high,[int]$current) {
        [void](Add-Label $title 19 ($top+5) 145 24)
        $slider = [System.Windows.Forms.TrackBar]::new()
        $slider.Name = 'Appearance' + ($title -replace '[^a-zA-Z]', '')
        $slider.Minimum = $low; $slider.Maximum = $high
        $slider.TickFrequency = 25
        $slider.Value = [math]::Clamp($current,$low,$high)
        $slider.Location = [System.Drawing.Point]::new(158,$top)
        $slider.Size = [System.Drawing.Size]::new(315,40)
        $dialog.Controls.Add($slider)
        $number = Add-Label "$($slider.Value)%" 481 ($top+4) 62 25
        $number.TextAlign = 'MiddleRight'
        $slider.Add_ValueChanged({ $number.Text = "$($slider.Value)%" }.GetNewClosure())
        return $slider
    }
    $heading = Add-Label 'Adjust the material. See it change below.' 20 16 518 28
    $heading.Font = [System.Drawing.Font]::new('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
    $subheading = Add-Label 'Changes are live. Cancel restores your previous appearance.' 20 45 525 23
    $subheading.ForeColor = [System.Drawing.Color]::DimGray

    function StartingIndex([string]$value) {
        $i = [array]::IndexOf($presets,$value)
        if ($i -ge 0) { return $i }
        return $presets.Count
    }
    $quota = Add-Select 'Usage color' 78 $names (StartingIndex ([string]$draft['quota']))
    $time = Add-Select 'Countdown color' 119 $names (StartingIndex ([string]$draft['time']))

    # Owner-draw colors so presets are recognizable before the user selects them.
    foreach ($pair in @(@($quota,'quota'),@($time,'time'))) {
        $combo = $pair[0]; $kind = [string]$pair[1]
        $combo.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
        $combo.ItemHeight = 25
        $combo.Add_DrawItem({
            param($sender,$e)
            if ($e.Index -lt 0) { return }
            $e.DrawBackground()
            $hex = if ($e.Index -eq $presets.Count) { [string]$custom[$kind] } else { [string]$sampleHex[$e.Index] }
            $color = [System.Drawing.ColorTranslator]::FromHtml($hex)
            $swatch = [System.Drawing.Rectangle]::new($e.Bounds.X+7,$e.Bounds.Y+5,30,[math]::Max(8,$e.Bounds.Height-10))
            $brush = [System.Drawing.SolidBrush]::new($color)
            $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(110,60,70,80))
            try {
                $e.Graphics.FillRectangle($brush,$swatch)
                $e.Graphics.DrawRectangle($pen,$swatch)
            } finally { $brush.Dispose();$pen.Dispose() }
            $text = if ($e.Index -eq $presets.Count) { "Custom  $hex" } else { [string]$names[$e.Index] }
            $bounds = [System.Drawing.Rectangle]::new($e.Bounds.X+45,$e.Bounds.Y+2,$e.Bounds.Width-47,$e.Bounds.Height-4)
            [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics,$text,$sender.Font,$bounds,$e.ForeColor,[System.Windows.Forms.TextFormatFlags]::VerticalCenter)
            $e.DrawFocusRectangle()
        }.GetNewClosure())
    }

    function Add-Chooser([string]$kind,[int]$top,[System.Windows.Forms.ComboBox]$combo) {
        $button = [System.Windows.Forms.Button]::new()
        $button.Name = 'Choose' + $kind
        $button.Text = 'Choose...'
        $button.Location = [System.Drawing.Point]::new(438,$top)
        $button.Size = [System.Drawing.Size]::new(104,29)
        $dialog.Controls.Add($button)
        $button.Add_Click({
            $picker = [System.Windows.Forms.ColorDialog]::new()
            try {
                $picker.FullOpen = $true
                $picker.AnyColor = $true
                $picker.Color = [System.Drawing.ColorTranslator]::FromHtml([string]$custom[$kind])
                if ($picker.ShowDialog($dialog) -eq [System.Windows.Forms.DialogResult]::OK) {
                    $c = $picker.Color
                    $custom[$kind] = '#{0:X2}{1:X2}{2:X2}' -f $c.R,$c.G,$c.B
                    $combo.SelectedIndex = $presets.Count
                    $combo.Invalidate()
                    & $previewChanged
                }
            } finally { $picker.Dispose() }
        }.GetNewClosure())
        return $button
    }

    # A genuine running pair of 400x17 Aero controls, not a static thumbnail.
    $preview = [System.Windows.Forms.Panel]::new()
    $preview.Name = 'LiveAeroPreview'
    $preview.BackColor = [System.Drawing.Color]::White
    $preview.Location = [System.Drawing.Point]::new(19,165)
    $preview.Size = [System.Drawing.Size]::new(524,146)
    $preview.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dialog.Controls.Add($preview)
    $usageLabel = [System.Windows.Forms.Label]::new()
    $usageLabel.Text = 'USAGE LIMIT     68%'
    $usageLabel.Location = [System.Drawing.Point]::new(16,10)
    $usageLabel.Size = [System.Drawing.Size]::new(475,24)
    $usageLabel.Font = [System.Drawing.Font]::new('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
    $preview.Controls.Add($usageLabel)
    $previewQuota = New-AeroProgressBar $preview 16 37 488 17 'quota'
    Set-AeroProgress $previewQuota 68
    $runLabel = [System.Windows.Forms.Label]::new()
    $runLabel.Text = 'RUN COUNTDOWN     75%'
    $runLabel.Location = [System.Drawing.Point]::new(16,73)
    $runLabel.Size = [System.Drawing.Size]::new(475,23)
    $runLabel.Font = [System.Drawing.Font]::new('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
    $preview.Controls.Add($runLabel)
    $previewTime = New-AeroProgressBar $preview 16 99 488 17 'time'
    Set-AeroProgress $previewTime 75
    $note = [System.Windows.Forms.Label]::new()
    $note.Text = 'These are the same animated renderers used in the scheduler.'
    $note.ForeColor = [System.Drawing.Color]::DimGray
    $note.Location = [System.Drawing.Point]::new(17,120)
    $note.Size = [System.Drawing.Size]::new(489,20)
    $note.Font = [System.Drawing.Font]::new('Segoe UI',8)
    $preview.Controls.Add($note)

    $material = Add-Select 'Liquid material' 324 @('Optical glass','Mirror enamel','Iridescent pearl') ([int]$draft['finish'])
    $material.Width = 379
    $lighting = Add-Select 'Studio lighting' 363 @('Product studio','Aero daylight','Neon showroom') ([int]$draft['lighting'])
    $lighting.Width = 379
    $shimmer = Add-Slider 'Reflection strength' 406 0 200 ([int]$draft['shimmer'])
    $speed = Add-Slider 'Reflection speed' 452 25 300 ([int]$draft['speed'])
    $enabled = [System.Windows.Forms.CheckBox]::new()
    $enabled.Name = 'AppearanceAeroEnabled'
    $enabled.Text = 'Enable Aero Liquid optics'
    $enabled.AutoSize = $true
    $enabled.Checked = [bool]$draft['aero']
    $enabled.Location = [System.Drawing.Point]::new(20,503)
    $dialog.Controls.Add($enabled)

    # Preview all edits immediately in the dialog and in the underlying app.
    # Settings persistence is intentionally deferred until the user clicks Save.
    $previewChanged = {
        $draft['quota'] = if ($quota.SelectedIndex -eq $presets.Count) { [string]$custom['quota'] } else { [string]$presets[$quota.SelectedIndex] }
        $draft['time'] = if ($time.SelectedIndex -eq $presets.Count) { [string]$custom['time'] } else { [string]$presets[$time.SelectedIndex] }
        $draft['finish'] = [int]$material.SelectedIndex
        $draft['lighting'] = [int]$lighting.SelectedIndex
        $draft['shimmer'] = [int]$shimmer.Value
        $draft['speed'] = [int]$speed.Value
        $draft['aero'] = [bool]$enabled.Checked
        Update-AeroAppearance $draft
    }.GetNewClosure()
    foreach ($control in @($quota,$time,$material,$lighting)) {
        $control.Add_SelectedIndexChanged({ & $previewChanged }.GetNewClosure())
    }
    foreach ($control in @($shimmer,$speed)) {
        $control.Add_ValueChanged({ & $previewChanged }.GetNewClosure())
    }
    $enabled.Add_CheckedChanged({ & $previewChanged }.GetNewClosure())
    [void](Add-Chooser 'quota' 78 $quota)
    [void](Add-Chooser 'time' 119 $time)

    $separator = [System.Windows.Forms.Label]::new()
    $separator.BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D
    $separator.Location = [System.Drawing.Point]::new(19,544)
    $separator.Size = [System.Drawing.Size]::new(524,2)
    $dialog.Controls.Add($separator)

    $defaults = [System.Windows.Forms.Button]::new()
    $defaults.Name = 'AppearanceDefaults'
    $defaults.Text = 'Defaults'
    $defaults.Location = [System.Drawing.Point]::new(19,568)
    $defaults.Size = [System.Drawing.Size]::new(98,33)
    $defaults.Add_Click({
        $quota.SelectedIndex=0;$time.SelectedIndex=1
        $material.SelectedIndex=0;$lighting.SelectedIndex=0
        $shimmer.Value=100;$speed.Value=100
        $enabled.Checked=$true
    }.GetNewClosure())
    $dialog.Controls.Add($defaults)
    $cancel = [System.Windows.Forms.Button]::new()
    $cancel.Name = 'AppearanceCancel'
    $cancel.Text = 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(305,568)
    $cancel.Size = [System.Drawing.Size]::new(102,33)
    $dialog.Controls.Add($cancel)
    $save = [System.Windows.Forms.Button]::new()
    $save.Name = 'AppearanceSave'
    $save.Text = 'Save and close'
    $save.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $save.Location = [System.Drawing.Point]::new(416,568)
    $save.Size = [System.Drawing.Size]::new(126,33)
    $dialog.Controls.Add($save)
    $dialog.AcceptButton = $save
    $dialog.CancelButton = $cancel

    $accepted = $false
    try {
        $result = $dialog.ShowDialog($Owner)
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            # Control event callbacks have already applied the final live state.
            & $previewChanged
            Queue-FormStateSave
            $accepted = $true
        }
    } finally {
        if (-not $accepted) { Update-AeroAppearance $previous }
        foreach ($bar in @($previewQuota,$previewTime)) {
            if ($bar) {
                [void]$script:aeroBars.Remove($bar)
                $bar.Dispose()
            }
        }
        $dialog.Dispose()
    }
}