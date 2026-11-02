# Application-specific, read-only presentation of persisted job outcomes.
function Show-CodexRunHistoryDialog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.Form]$Owner,
          [Parameter(Mandatory)][string]$Directory)
    $dialog=[System.Windows.Forms.Form]::new()
    $dialog.Text='Recent Codex run results'
    $dialog.StartPosition='CenterParent'
    $dialog.ClientSize=[Drawing.Size]::new(960,460)
    $dialog.MinimumSize=[Drawing.Size]::new(760,330)
    $grid=[System.Windows.Forms.DataGridView]::new()
    $grid.Dock='Fill'
    $grid.ReadOnly=$true
    $grid.AllowUserToAddRows=$false
    $grid.AllowUserToDeleteRows=$false
    $grid.RowHeadersVisible=$false
    $grid.SelectionMode='FullRowSelect'
    $grid.AutoSizeColumnsMode='Fill'
    foreach($column in @(@('When','Finished (local)'),@('Status','Result'),@('ExitCode','Exit'),@('Attempt','Attempt'),@('NextJob','Next task'),@('Message','Details'))){
        [void]$grid.Columns.Add($column[0],$column[1])
    }
    $grid.Columns['When'].FillWeight=150
    $grid.Columns['Status'].FillWeight=95
    $grid.Columns['ExitCode'].FillWeight=48
    $grid.Columns['Attempt'].FillWeight=68
    $grid.Columns['NextJob'].FillWeight=190
    $grid.Columns['Message'].FillWeight=295
    $dialog.Controls.Add($grid)
    try {
        foreach($entry in @(Get-CodexRunHistory -Directory $Directory -Limit 100)){
            $row=$grid.Rows.Add($entry.When.ToString('yyyy-MM-dd HH:mm'),$entry.Status,
                $(if($null -eq $entry.ExitCode){''}else{[string]$entry.ExitCode}),
                $(if($null -eq $entry.Attempt){''}else{[string]$entry.Attempt}),
                $entry.NextJob,$entry.Message)
            $grid.Rows[$row].Tag=$entry.Name
            $grid.Rows[$row].Cells['NextJob'].ToolTipText=[string]$entry.NextJob
        }
        if($grid.Rows.Count -eq 0){$dialog.Text+=' (no results yet)'}
        [void]$dialog.ShowDialog($Owner)
    } finally {$dialog.Dispose()}
}
