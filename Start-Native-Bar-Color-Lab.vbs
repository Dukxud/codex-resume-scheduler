Option Explicit
Dim shell, files, folder, script
Set files = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
folder = files.GetParentFolderName(WScript.ScriptFullName)
script = files.BuildPath(folder, "NativeBarColorLab.ps1")
If Not files.FileExists(script) Then
    MsgBox "NativeBarColorLab.ps1 is missing. Extract both files together.", vbCritical, "Native Bar Color Lab"
    WScript.Quit 1
End If
On Error Resume Next
shell.Run "pwsh.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File " & Chr(34) & script & Chr(34), 0, False
If Err.Number <> 0 Then
    MsgBox "Unable to start PowerShell 7: " & Err.Description, vbCritical, "Native Bar Color Lab"
    WScript.Quit 1
End If
On Error GoTo 0
