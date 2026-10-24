@echo off
setlocal EnableDelayedExpansion
title Battle XP G350 - Connection Test
color 0B

echo ============================================================
echo        BATTLE XP G350 - USB CABLE CONNECTION TEST
echo ============================================================
echo.
echo Checking connection to the console...
echo.

set "IP=192.168.137.2"
ping -n 1 -w 1000 !IP! >nul 2>&1
if errorlevel 1 (
    set "IP=192.168.7.2"
    ping -n 1 -w 1000 !IP! >nul 2>&1
    if errorlevel 1 goto :failed
)

:success
color 0A
echo [OK] Console detected and responding at !IP!.
echo.
echo Testing SSH / SFTP service on Port 22...
powershell -NoProfile -Command "$client = New-Object System.Net.Sockets.TcpClient; try { $iar = $client.BeginConnect('%IP%', 22, $null, $null); $wait = $iar.AsyncWaitHandle.WaitOne(2000, $false); if ($wait -and $client.Connected) { Write-Host ' [OK] SSH Port 22 is ACTIVE and ready for file transfers.' -ForegroundColor Green } else { Write-Host ' [WARNING] Console responds, but SSH Port 22 is not running yet.' -ForegroundColor Yellow; Write-Host '           Launch USB Network Manager on your console and press [A].' -ForegroundColor Yellow } } catch { Write-Host ' [ERROR] Could not connect to SSH Port 22.' -ForegroundColor Red } finally { $client.Close() }"
echo.
echo ============================================================
echo  CONNECTION DETAILS (WinSCP / FileZilla / Windows Explorer)
echo ============================================================
echo   - Protocol : SFTP
echo   - Host     : !IP!
echo   - Port     : 22
echo   - Username : ark
echo   - Password : ark
echo   - Path     : /roms/
echo.
echo Windows File Explorer network path: \\!IP!\roms
echo.
echo TIP: Use the IP shown above. Wi-Fi sharing ON = 192.168.137.2, OFF = 192.168.7.2.
echo ============================================================
echo.
goto :end

:failed
color 0C
echo [FAILED] No response detected from 192.168.137.2 or 192.168.7.2.
echo.
echo Troubleshooting Steps:
echo 1. Ensure the USB-A to USB-C data cable is connected firmly.
echo 2. On your console, launch 'USB Network Manager' from TOOLS (or PORTS).
echo 3. Check USB Mode: if it says 'USB HOST', press [X] to switch to Wired PC mode.
echo 4. Press [A] (Start Services) to initialize the USB network gadget.
echo.

:end
pause
