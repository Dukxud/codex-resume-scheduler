# Generic glossy Windows Presentation Foundation progress control.
# The host supplies every color, geometry and accessible label; no scheduler dependency.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName WindowsFormsIntegration
$script:progressValues=[System.Runtime.CompilerServices.ConditionalWeakTable[System.Windows.Forms.Integration.ElementHost,System.Object]]::new()

function New-FlowingProgressView {
    param(
        [System.Windows.Forms.Control]$Parent,
        [int]$X, [int]$Y, [int]$Width, [int]$Height,
        [Parameter(Mandatory)][hashtable]$Colors,
        [Parameter(Mandatory)][string]$AccessibleName
    )
    foreach ($name in @('BaseTop','BaseBottom','Track','Outline')) {
        if (-not $Colors.ContainsKey($name) -or
            [string]$Colors[$name] -notmatch '^#[0-9a-fA-F]{6}$') {
            throw "FlowingProgress requires a valid $name color in #RRGGBB form."
        }
    }
    $palette = $Colors
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
    $elementHost.AccessibleName = $AccessibleName
    $Parent.Controls.Add($elementHost)
    return $elementHost
}

function Get-FlowingProgressViewValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.Integration.ElementHost]$Bar)
    $saved=[object]$null
    if($script:progressValues.TryGetValue($Bar,[ref]$saved)) { return $saved.Percent }
    return $null
}

function Set-FlowingProgressViewState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.Integration.ElementHost]$Bar,$Percent)
    if($Bar.IsDisposed){return}
    $value=if($null -eq $Percent){$null}else{[double][math]::Clamp([double]$Percent,0,100)}
    $existing=[object]$null
    if($script:progressValues.TryGetValue($Bar,[ref]$existing) -and $existing.Percent -eq $value){return}
    [void]$script:progressValues.Remove($Bar)
    $script:progressValues.Add($Bar,[pscustomobject]@{Percent=$value})
    # Host.Tag remains entirely caller-owned; the progress state is private
    # to this module and is released when the ElementHost is collected.
    $Bar.Child.Value=if($null -eq $value){0.0}else{$value}
}

function Set-FlowingProgressViewColors {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Integration.ElementHost]$Bar,
        [Parameter(Mandatory)][hashtable]$Colors
    )
    if ($Bar.IsDisposed) { return }
    foreach ($name in @('BaseTop','BaseBottom','Track','Outline')) {
        if (-not $Colors.ContainsKey($name) -or
            [string]$Colors[$name] -notmatch '^#[0-9a-fA-F]{6}
) {
            throw "Invalid $name color; expected #RRGGBB."
        }
    }
    $progress = [System.Windows.Controls.ProgressBar]$Bar.Child
    if (-not $progress) { throw 'FlowingProgress has no WPF progress child.' }
    [void]$progress.ApplyTemplate()
    $track = [System.Windows.Controls.Border]$progress.Template.FindName('PART_Track',$progress)
    $indicator = [System.Windows.Controls.Border]$progress.Template.FindName('PART_Indicator',$progress)
    if (-not $track -or -not $indicator) { throw 'FlowingProgress template surfaces are unavailable.' }
    $interior = [System.Windows.Controls.Grid]$indicator.Child
    $fill = [System.Windows.Controls.Border]$interior.Children[0]
    $gradient = [System.Windows.Media.LinearGradientBrush]$fill.Background
    if (-not $gradient -or $gradient.GradientStops.Count -lt 2) {
        throw 'FlowingProgress gradient is unavailable.'
    }
    if ($gradient.IsFrozen) {
        $gradient = $gradient.CloneCurrentValue()
        $fill.Background = $gradient
    }
    $gradient.GradientStops[0].Color = [System.Windows.Media.ColorConverter]::ConvertFromString($Colors.BaseTop)
    $gradient.GradientStops[1].Color = [System.Windows.Media.ColorConverter]::ConvertFromString($Colors.BaseBottom)
    $converter = [System.Windows.Media.BrushConverter]::new()
    $track.Background = $converter.ConvertFromString($Colors.Track)
    $track.BorderBrush = $converter.ConvertFromString($Colors.Outline)
}

Export-ModuleMember -Function New-FlowingProgressView,Get-FlowingProgressViewValue,Set-FlowingProgressViewState,Set-FlowingProgressViewColors
