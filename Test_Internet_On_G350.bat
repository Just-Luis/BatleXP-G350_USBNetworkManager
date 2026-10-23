@echo off
title Test Internet Tethering BatleXP G350
color 0B
echo ============================================================
echo   BATLEXP G350 - TEST DE CONEXION A INTERNET (TETHERING)
echo ============================================================
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0Test_Internet_On_G350.ps1"
echo.
pause
