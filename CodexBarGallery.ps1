# Real WPF progress controls, hosted in the scheduler's existing WinForms process.
# Preview only: these are live percentage-driven controls, not picture assets.
function New-MaterialProgressBar {
    param(
        [System.Windows.Forms.Control]$Parent,
        [int]$X, [int]$Y, [int]$Width, [int]$Height,
        [ValidateSet('crystal','gel','machined','prism')][string]$Style
    )
    $themes = @{
        crystal = @{
            EdgeTop='#F8FFFF'; EdgeBottom='#56758A'; Face='#13293E'; Well='#071523'
            FillTop='#B7F7FF'; FillMid='#0DCAF3'; FillBottom='#064E9C'; Halo='#00BFFF'
            Radius='18'; FillRadius='14'; Lip='#D5F8FF'; Inner='#9DD6E7'; Glow='0.45'; TopGloss='#90FFFFFF'
        }
        gel = @{
            EdgeTop='#B6FFF2'; EdgeBottom='#126958'; Face='#0B4545'; Well='#04262A'
            FillTop='#AFFFF3'; FillMid='#1CEABF'; FillBottom='#006F69'; Halo='#32FFDA'
            Radius='20'; FillRadius='17'; Lip='#B1FFF1'; Inner='#6CFFEB'; Glow='0.55'; TopGloss='#B0FFFFFF'
        }
        machined = @{
            EdgeTop='#F2F3F5'; EdgeBottom='#5D6570'; Face='#3A434E'; Well='#111920'
            FillTop='#AAFFA8'; FillMid='#2ACD73'; FillBottom='#07572B'; Halo='#27C16B'
            Radius='14'; FillRadius='9'; Lip='#F2F4F8'; Inner='#87949E'; Glow='0.27'; TopGloss='#75FFFFFF'
        }
        prism = @{
            EdgeTop='#FAD9FF'; EdgeBottom='#624B8B'; Face='#252045'; Well='#100C2B'
            FillTop='#F9DDFF'; FillMid='#A94DFF'; FillBottom='#3522A1'; Halo='#C860FF'
            Radius='18'; FillRadius='13'; Lip='#FFC9FF'; Inner='#C99BF9'; Glow='0.55'; TopGloss='#A5FFFFFF'
        }
    }
    $theme = $themes[$Style]
    # The ProgressBar template contains the actual native WPF PART_Track and
    # PART_Indicator. WPF sets the indicator width from Value automatically.
    # The glint animation is confined to the indicator; it never alters Value.
    $xaml = @'
<ProgressBar xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             Minimum="0" Maximum="100" Value="68"
             Focusable="False" IsHitTestVisible="False">
 <ProgressBar.Template>
  <ControlTemplate TargetType="{x:Type ProgressBar}">
   <Grid ClipToBounds="False">
    <Border x:Name="MetalHousing" CornerRadius="__RADIUS__" BorderThickness="1.4"
            BorderBrush="__LIP__">
      <Border.Background>
       <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
        <GradientStop Offset="0" Color="__EDGE_TOP__"/>
        <GradientStop Offset="0.23" Color="__FACE__"/>
        <GradientStop Offset="0.64" Color="__WELL__"/>
        <GradientStop Offset="1" Color="__EDGE_BOTTOM__"/>
       </LinearGradientBrush>
      </Border.Background>
      <Border.Effect>
       <DropShadowEffect Color="#000000" ShadowDepth="4" BlurRadius="9" Opacity="0.75"/>
      </Border.Effect>
    </Border>
    <Border Margin="2" CornerRadius="__RADIUS__" BorderThickness="1.1"
            BorderBrush="__INNER__" Background="__WELL__"/>
    <Border x:Name="PART_Track" Margin="5,5,5,5" CornerRadius="__FILL_RADIUS__"
            Background="__WELL__" BorderThickness="0"/>
    <Border x:Name="PART_Indicator" Margin="5,5,5,5"
            HorizontalAlignment="Left" CornerRadius="__FILL_RADIUS__"
            ClipToBounds="True">
      <Grid ClipToBounds="True">
       <Border CornerRadius="__FILL_RADIUS__">
        <Border.Background>
         <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
          <GradientStop Offset="0" Color="__FILL_TOP__"/>
          <GradientStop Offset="0.28" Color="__FILL_MID__"/>
          <GradientStop Offset="0.57" Color="__FILL_BOTTOM__"/>
          <GradientStop Offset="0.85" Color="__FILL_MID__"/>
          <GradientStop Offset="1" Color="__FILL_BOTTOM__"/>
         </LinearGradientBrush>
        </Border.Background>
        <Border.Effect>
         <DropShadowEffect Color="__HALO__" BlurRadius="9"
                           ShadowDepth="0" Opacity="__GLOW__"/>
        </Border.Effect>
       </Border>
       <Border VerticalAlignment="Top" Height="8" Margin="2,1,2,0"
               CornerRadius="9,9,4,4" Background="__TOP_GLOSS__"/>
       <Border VerticalAlignment="Bottom" Height="2" Margin="3,0,3,2"
               CornerRadius="2" Background="#55FFFFFF"/>
       <Rectangle x:Name="FlowGlint" Width="86" HorizontalAlignment="Left"
                  IsHitTestVisible="False" Opacity="0.88">
        <Rectangle.Fill>
         <LinearGradientBrush StartPoint="0,0.5" EndPoint="1,0.5">
          <GradientStop Color="#00FFFFFF" Offset="0"/>
          <GradientStop Color="#10FFFFFF" Offset="0.2"/>
          <GradientStop Color="#F0FFFFFF" Offset="0.49"/>
          <GradientStop Color="#10FFFFFF" Offset="0.8"/>
          <GradientStop Color="#00FFFFFF" Offset="1"/>
         </LinearGradientBrush>
        </Rectangle.Fill>
        <Rectangle.RenderTransform>
         <TranslateTransform X="-86"/>
        </Rectangle.RenderTransform>
       </Rectangle>
      </Grid>
    </Border>
    <Border Margin="2,2,2,0" BorderThickness="0,1,0,0"
            BorderBrush="#A8FFFFFF" CornerRadius="__RADIUS__"
            IsHitTestVisible="False" />
   </Grid>
   <ControlTemplate.Triggers>
    <EventTrigger RoutedEvent="FrameworkElement.Loaded">
     <BeginStoryboard>
      <Storyboard>
       <DoubleAnimation Storyboard.TargetName="FlowGlint"
                        Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.X)"
                        From="-86" To="600" Duration="0:0:2.8" RepeatBehavior="Forever"/>
      </Storyboard>
     </BeginStoryboard>
    </EventTrigger>
   </ControlTemplate.Triggers>
  </ControlTemplate>
 </ProgressBar.Template>
</ProgressBar>
'@
    $replacements = @{
        '__RADIUS__'=$theme.Radius; '__FILL_RADIUS__'=$theme.FillRadius;
        '__EDGE_TOP__'=$theme.EdgeTop; '__EDGE_BOTTOM__'=$theme.EdgeBottom;
        '__FACE__'=$theme.Face; '__WELL__'=$theme.Well; '__LIP__'=$theme.Lip;
        '__INNER__'=$theme.Inner; '__FILL_TOP__'=$theme.FillTop;
        '__FILL_MID__'=$theme.FillMid; '__FILL_BOTTOM__'=$theme.FillBottom;
        '__HALO__'=$theme.Halo; '__GLOW__'=$theme.Glow;
        '__TOP_GLOSS__'=$theme.TopGloss
    }
    foreach ($key in $replacements.Keys) { $xaml = $xaml.Replace($key,[string]$replacements[$key]) }
    $control = [System.Windows.Markup.XamlReader]::Parse($xaml)
    $materialHost = [System.Windows.Forms.Integration.ElementHost]::new()
    $materialHost.Location = [System.Drawing.Point]::new($X,$Y)
    $materialHost.Size = [System.Drawing.Size]::new($Width,$Height)
    $materialHost.BackColor = $Parent.BackColor
    $materialHost.Child = $control
    $materialHost.Tag = $Style
    $materialHost.AccessibleName = "$Style animated progress bar"
    $Parent.Controls.Add($materialHost)
    return $materialHost
}

function New-SchedulerBarGallery {
    $gallery = [System.Windows.Forms.Form]::new()
    $gallery.Text = 'Codex Scheduler — Live 3D Bar Lab (Preview)'
    $gallery.ClientSize = [System.Drawing.Size]::new(860,670)
    $gallery.BackColor = [System.Drawing.Color]::FromArgb(21,27,38)
    $gallery.StartPosition = 'CenterParent'
    $gallery.FormBorderStyle = 'FixedDialog'
    $gallery.MaximizeBox = $false
    $gallery.MinimizeBox = $false
    $title = [System.Windows.Forms.Label]::new()
    $title.Text = 'LIVE MATERIAL LAB  |  Actual Windows WPF controls'
    $title.ForeColor = [System.Drawing.Color]::FromArgb(240,244,250)
    $title.Font = [System.Drawing.Font]::new('Segoe UI',14,[System.Drawing.FontStyle]::Bold)
    $title.Location = [System.Drawing.Point]::new(25,16)
    $title.Size = [System.Drawing.Size]::new(810,37)
    $gallery.Controls.Add($title)
    $note = [System.Windows.Forms.Label]::new()
    $note.Text = 'All four bars are live. The percentage slider changes their actual fill. The shine animates continuously.'
    $note.ForeColor = [System.Drawing.Color]::FromArgb(178,195,216)
    $note.Location = [System.Drawing.Point]::new(27,59)
    $note.Size = [System.Drawing.Size]::new(810,35)
    $gallery.Controls.Add($note)

    $entries = @(
        @{ Key='crystal'; Name='A — Optical Crystal'; Detail='Polished glass + silver rim' },
        @{ Key='gel'; Name='B — Liquid Gel'; Detail='Translucent aqua volume' },
        @{ Key='machined'; Name='C — Machined Alloy'; Detail='Recessed green core + steel' },
        @{ Key='prism'; Name='D — Prism Energy'; Detail='Violet glass + illuminated edge' }
    )
    $bars = [System.Collections.Generic.List[System.Windows.Forms.Integration.ElementHost]]::new()
    $valueLabels = [System.Collections.Generic.List[System.Windows.Forms.Label]]::new()
    foreach ($i in 0..3) {
        $entry = $entries[$i]
        $top = 104 + $i * 112
        $row = [System.Windows.Forms.Panel]::new()
        $row.Location = [System.Drawing.Point]::new(25,$top)
        $row.Size = [System.Drawing.Size]::new(809,100)
        $row.BackColor = [System.Drawing.Color]::FromArgb(30,38,51)
        $row.BorderStyle = 'FixedSingle'
        $gallery.Controls.Add($row)
        $name = [System.Windows.Forms.Label]::new()
        $name.Text = $entry.Name
        $name.ForeColor = [System.Drawing.Color]::White
        $name.Font = [System.Drawing.Font]::new('Segoe UI',11,[System.Drawing.FontStyle]::Bold)
        $name.Location = [System.Drawing.Point]::new(14,10)
        $name.Size = [System.Drawing.Size]::new(250,24)
        $row.Controls.Add($name)
        $detail = [System.Windows.Forms.Label]::new()
        $detail.Text = $entry.Detail
        $detail.ForeColor = [System.Drawing.Color]::FromArgb(173,192,209)
        $detail.Location = [System.Drawing.Point]::new(14,35)
        $detail.Size = [System.Drawing.Size]::new(245,22)
        $row.Controls.Add($detail)
        $material = New-MaterialProgressBar $row 272 25 500 40 $entry.Key
        $bars.Add($material)
        $percentLabel = [System.Windows.Forms.Label]::new()
        $percentLabel.Text = '68% — sample data'
        $percentLabel.ForeColor = [System.Drawing.Color]::FromArgb(192,210,230)
        $percentLabel.Location = [System.Drawing.Point]::new(274,70)
        $percentLabel.Size = [System.Drawing.Size]::new(470,20)
        $percentLabel.Name = "GalleryValue_$($entry.Key)"
        $row.Controls.Add($percentLabel)
        $valueLabels.Add($percentLabel)
    }

    $sliderLabel = [System.Windows.Forms.Label]::new()
    $sliderLabel.Text = 'PROGRESS  |  68% (sample)'
    $sliderLabel.ForeColor = [System.Drawing.Color]::White
    $sliderLabel.Location = [System.Drawing.Point]::new(28,564)
    $sliderLabel.Size = [System.Drawing.Size]::new(255,25)
    $gallery.Controls.Add($sliderLabel)
    $slider = [System.Windows.Forms.TrackBar]::new()
    $slider.Minimum = 0
    $slider.Maximum = 100
    $slider.Value = 68
    $slider.TickFrequency = 10
    $slider.Location = [System.Drawing.Point]::new(278,559)
    $slider.Size = [System.Drawing.Size]::new(510,45)
    $gallery.Controls.Add($slider)
    $slider.Add_ValueChanged({
        $value = $slider.Value
        $sliderLabel.Text = "PROGRESS  |  $value% (sample)"
        for ($i=0; $i -lt $bars.Count; $i++) {
            $bars[$i].Child.Value = [double]$value
            $valueLabels[$i].Text = "$value% — sample data"
        }
    })
    $footer = [System.Windows.Forms.Label]::new()
    $footer.Text = 'Preview only • no scheduled jobs or saved preferences are modified'
    $footer.ForeColor = [System.Drawing.Color]::FromArgb(150,169,190)
    $footer.Location = [System.Drawing.Point]::new(28,621)
    $footer.Size = [System.Drawing.Size]::new(760,25)
    $gallery.Controls.Add($footer)

    return [pscustomobject]@{ Form=$gallery; Bars=$bars; ValueLabels=$valueLabels; Slider=$slider }
}

function Show-SchedulerBarGallery {
    param([System.Windows.Forms.Form]$Owner)
    $lab = New-SchedulerBarGallery
    try {
        [void]$lab.Form.ShowDialog($Owner)
    } finally {
        $lab.Form.Dispose()
    }
}
