' Launch the normal Windows Forms PowerShell app without a terminal on the desktop.
' WScript is provided by Windows; this package contains no compiled launcher.
Option Explicit
Dim shell, files, folder, script, command, status, pwsh
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
folder = files.GetParentFolderName(WScript.ScriptFullName)
script = files.BuildPath(folder, "CodexResumeScheduler.ps1")
If Not files.FileExists(script) Then
    MsgBox "CodexResumeScheduler.ps1 is missing. Extract the complete release ZIP.", vbCritical, "Codex Resume Scheduler"
    WScript.Quit 1
End If
' Resolve Microsoft's installed PowerShell by absolute path. Never allow a
' repository working directory or PATH entry to substitute another pwsh.exe.
pwsh = files.BuildPath(shell.ExpandEnvironmentStrings("%ProgramFiles%"), "PowerShell\7\pwsh.exe")
If Not files.FileExists(pwsh) Then
    MsgBox "PowerShell 7 not found in Program Files. Install the official x64 PowerShell 7 release.", vbCritical, "Codex Resume Scheduler"
    WScript.Quit 2
End If
command = Chr(34) & pwsh & Chr(34) & " -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File " & Chr(34) & script & Chr(34)
On Error Resume Next
status = shell.Run(command, 0, False)
If Err.Number <> 0 Then
    MsgBox "Unable to start PowerShell 7: " & Err.Description, vbCritical, "Codex Resume Scheduler"
    WScript.Quit 1
End If
On Error GoTo 0
