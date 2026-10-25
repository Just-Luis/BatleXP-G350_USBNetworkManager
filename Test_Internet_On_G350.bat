@echo off
setlocal EnableDelayedExpansion
title Battle XP G350 - Internet Tethering Test
color 0B

echo ============================================================
echo   BATTLE XP G350 - INTERNET TETHERING TEST
echo ============================================================
echo.

echo [1/2] Checking local connection to the console...
set "IP=192.168.137.2"
ping -n 1 -w 1000 !IP! >nul 2>&1
if errorlevel 1 (
    set "IP=192.168.7.2"
    ping -n 1 -w 1000 !IP! >nul 2>&1
    if errorlevel 1 (
        color 0C
        echo  [ERROR] Could not reach console at 192.168.137.2 or 192.168.7.2.
        echo  Make sure the USB cable is plugged in and services are started.
        goto :done
    )
)
color 0A
echo  [OK] Console connected and responding at !IP!.
echo.
echo [2/2] Checking live status on console display...
echo  Look at your console screen under 'USB Network Manager':
echo    - GATEWAY  : Should say 192.168.137.1 (Online)
echo    - INTERNET : Should say ONLINE (PortMaster Ready)
echo.
echo If Internet is OFFLINE:
echo  Ensure Windows Internet Connection Sharing (ICS) is enabled on your Wi-Fi adapter.

:done
echo.
pause
