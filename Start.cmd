@echo off
rem Startet "Apps deinstallieren". Es erscheint genau eine Admin-Abfrage.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0AppsDeinstallieren.ps1"
