' Console-free Windows GUI entrypoint. Prefer the compiled GUI-subsystem launcher.
Option Explicit
Dim shell, files, folder, exe
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
folder = files.GetParentFolderName(WScript.ScriptFullName)
exe = files.BuildPath(folder, "CodexScheduler.exe")
If Not files.FileExists(exe) Then
    MsgBox "CodexScheduler.exe is missing. Download the versioned release ZIP, not the source archive.", vbCritical, "Codex Resume Scheduler"
    WScript.Quit 1
End If
shell.Run Chr(34) & exe & Chr(34), 1, False
