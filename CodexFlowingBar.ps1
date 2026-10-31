# Native .NET Windows Presentation Foundation (WPF) animated progress bars,
# hosted inside the existing WinForms scheduler. No external DLLs or executables.
# WPF owns the compositor animation; the scheduled percentage never oscillates.
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName WindowsFormsIntegration

function New-FlowingProgressBar {
    param(
        [System.Windows.Forms.Control]$Parent,
        [int]$X, [int]$Y, [int]$Width, [int]$Height,
        [ValidateSet('quota','time')][string]$Kind
    )
    $palette = if ($Kind -eq 'quota') {
        @{ BaseTop='#5DE0B5'; BaseBottom='#14805D'; Track='#E5F1EC'; Outline='#B3CFC2' }
    } else {
        @{ BaseTop='#76B5F9'; BaseBottom='#2566BC'; Track='#E2ECFA'; Outline='#B4C8E5' }
    }
    $markup = @'
<ProgressBar xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             Minimum="0" Maximum="100" Value="0" Focusable="False"
             Background="Transparent" BorderThickness="0">
  <ProgressBar.Template>
    <ControlTemplate TargetType="{x:Type ProgressBar}">
      <Grid ClipToBounds="True">
        <Border x:Name="PART_Track" Background="__TRACK__"
                CornerRadius="8" BorderThickness="1" BorderBrush="__OUTLINE__"/>
        <Border x:Name="PART_Indicator" CornerRadius="8" ClipToBounds="True"
                HorizontalAlignment="Left">
          <Grid ClipToBounds="True">
            <Border CornerRadius="8">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                  <GradientStop Color="__TOP__" Offset="0"/>
                  <GradientStop Color="__BOTTOM__" Offset="1"/>
                </LinearGradientBrush>
              </Border.Background>
            </Border>
            <Border CornerRadius="8,8,0,0" Background="#65FFFFFF"
                    VerticalAlignment="Top" Height="7"/>
            <Rectangle x:Name="FlowGlint" HorizontalAlignment="Left" Width="115"
                       IsHitTestVisible="False">
              <Rectangle.Fill>
                <LinearGradientBrush StartPoint="0,0.5" EndPoint="1,0.5">
                  <GradientStop Color="#00FFFFFF" Offset="0"/>
                  <GradientStop Color="#0AFFFFFF" Offset="0.22"/>
                  <GradientStop Color="#DFFFFFFF" Offset="0.50"/>
                  <GradientStop Color="#0AFFFFFF" Offset="0.78"/>
                  <GradientStop Color="#00FFFFFF" Offset="1"/>
                </LinearGradientBrush>
              </Rectangle.Fill>
              <Rectangle.RenderTransform>
                <TranslateTransform X="-115"/>
              </Rectangle.RenderTransform>
            </Rectangle>
          </Grid>
        </Border>
      </Grid>
      <ControlTemplate.Triggers>
        <EventTrigger RoutedEvent="FrameworkElement.Loaded">
          <BeginStoryboard>
            <Storyboard>
              <DoubleAnimation Storyboard.TargetName="FlowGlint"
                               Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.X)"
                               From="-115" To="425" Duration="0:0:2.4"
                               RepeatBehavior="Forever"/>
            </Storyboard>
          </BeginStoryboard>
        </EventTrigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>
  </ProgressBar.Template>
</ProgressBar>
'@
    foreach ($pair in @(
        @('__TRACK__',$palette.Track),
        @('__OUTLINE__',$palette.Outline),
        @('__TOP__',$palette.BaseTop),
        @('__BOTTOM__',$palette.BaseBottom)
    )) { $markup = $markup.Replace($pair[0],$pair[1]) }
    $progress = [System.Windows.Markup.XamlReader]::Parse($markup)
    $elementHost = [System.Windows.Forms.Integration.ElementHost]::new()
    $elementHost.Location = [System.Drawing.Point]::new($X,$Y)
    $elementHost.Size = [System.Drawing.Size]::new($Width,$Height)
    $elementHost.BackColor = $Parent.BackColor
    $elementHost.Child = $progress
    $elementHost.AccessibleName = if ($Kind -eq 'quota') { 'Usage remaining' } else { 'Time until scheduled run' }
    $elementHost.Tag = $null # null means no accepted percentage; draw an empty track.
    $Parent.Controls.Add($elementHost)
    return $elementHost
}

function Set-FlowingProgress {
    param(
        [System.Windows.Forms.Integration.ElementHost]$Bar,
        $Percent
    )
    $value = if ($null -eq $Percent) { $null }
             else { [double][math]::Clamp([double]$Percent,0,100) }
    if ($Bar.Tag -eq $value) { return }
    $Bar.Tag = $value
    $Bar.Child.Value = if ($null -eq $value) { 0.0 } else { $value }
}
