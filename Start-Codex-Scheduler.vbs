' Double-click this launcher for a GUI with no associated terminal window.
' The scheduler and its scheduled jobs keep writing their normal local log files.
Option Explicit
Dim shell, files, folder, command
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
folder = files.GetParentFolderName(WScript.ScriptFullName)
command = "pwsh.exe -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & folder & "\CodexResumeScheduler.ps1" & Chr(34)
shell.Run command, 0, False
