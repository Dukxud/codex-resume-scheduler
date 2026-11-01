' Windows Script Host performs the scheduled launch without displaying a terminal.
' Wait for PowerShell: Task Scheduler must track the actual Codex process lifetime.
Option Explicit
Dim shell, files, folder, script, jobFile, command, status, pwsh
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
If WScript.Arguments.Count <> 1 Then WScript.Quit 2
folder = files.GetParentFolderName(WScript.ScriptFullName)
script = files.BuildPath(folder, "CodexResumeScheduler.ps1")
jobFile = WScript.Arguments(0)
If Not files.FileExists(script) Or Not files.FileExists(jobFile) Then WScript.Quit 2
' Task Scheduler may use the repository as its working directory;
' an unqualified pwsh.exe there could be malicious. Require official x64 path.
pwsh = files.BuildPath(shell.ExpandEnvironmentStrings("%ProgramFiles%"), "PowerShell\7\pwsh.exe")
If Not files.FileExists(pwsh) Then WScript.Quit 2
command = Chr(34) & pwsh & Chr(34) & " -NoLogo -NoProfile -ExecutionPolicy Bypass -File " & Chr(34) & script & Chr(34) & _
          " -RunJob -JobFile " & Chr(34) & jobFile & Chr(34)
On Error Resume Next
status = shell.Run(command, 0, True)
If Err.Number <> 0 Then
    Dim errorPath, errFile
    errorPath = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\CodexResumeScheduler"
    If Not files.FolderExists(errorPath) Then files.CreateFolder(errorPath)
    Set errFile = files.OpenTextFile(files.BuildPath(errorPath, "runner-launch-errors.log"), 8, True)
    errFile.WriteLine Now & " " & Err.Description
    errFile.Close
    WScript.Quit 1
End If
On Error GoTo 0
WScript.Quit status
