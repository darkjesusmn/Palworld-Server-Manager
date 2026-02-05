' Palworld Server Manager - Launcher
' This launcher MUST be in the same folder as Palworld_Server_Manager.ps1
' It will not work if moved to a different location

Set objFSO = CreateObject("Scripting.FileSystemObject")
Set objShell = CreateObject("WScript.Shell")

' Get the directory where this VBS file is located
strScriptPath = objFSO.GetParentFolderName(WScript.ScriptFullName)

' Build the full path to the PowerShell script
strPSScript = objFSO.BuildPath(strScriptPath, "Palworld_Server_Manager.ps1")

' Check if the PowerShell script exists
if not objFSO.FileExists(strPSScript) then
    MsgBox "ERROR: Palworld_Server_Manager.ps1 not found!" & vbCrLf & vbCrLf & _
           "This launcher must be in the SAME FOLDER as Palworld_Server_Manager.ps1" & vbCrLf & vbCrLf & _
           "Current location: " & strScriptPath, _
           vbCritical, "Launcher Error"
    WScript.Quit 1
end if

' Build the command to execute
strCommand = "powershell.exe -ExecutionPolicy RemoteSigned -File """ & strPSScript & """"

' Run the PowerShell script silently (0 = hidden window)
objShell.Run strCommand, 0, False
