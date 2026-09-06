@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -File "%~dp0tools\agent.ps1" launch
