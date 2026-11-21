@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Manage.ps1" -Action Start
if errorlevel 1 echo Operation failed. Read the error above.
pause
