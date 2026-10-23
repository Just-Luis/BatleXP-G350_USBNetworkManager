@echo off
setlocal
title Test de Conexion BatleXP G350
color 0b
echo ============================================================
echo       BatleXP G350 - TEST DE CONEXION POR CABLE USB
echo ============================================================
echo.
echo Verificando conexion con la consola (192.168.7.2)...
echo.

ping -n 2 -w 1000 192.168.7.2 >nul 2>&1
if errorlevel 1 goto :failed

:success
color 0a
echo [OK] La consola responde a la red USB (192.168.7.2).
echo.
echo Probando servicio SSH en el puerto 22...
powershell -NoProfile -Command "$client = New-Object System.Net.Sockets.TcpClient; try { $iar = $client.BeginConnect('192.168.7.2', 22, $null, $null); $wait = $iar.AsyncWaitHandle.WaitOne(2000, $false); if ($wait -and $client.Connected) { Write-Host '[OK] Puerto SSH 22 ACTIVO y listo para transferir archivos.' -ForegroundColor Green } else { Write-Host '[AVISO] La red responde, pero el puerto SSH 22 aun no esta activo.' -ForegroundColor Yellow } } catch { Write-Host '[ERROR] No se pudo conectar al puerto SSH 22.' -ForegroundColor Red } finally { $client.Close() }"
echo.
echo Datos de conexion para FileZilla / WinSCP / Explorador:
echo   - Protocolo : SFTP
echo   - Servidor  : 192.168.7.2
echo   - Puerto    : 22
echo   - Usuario   : ark
echo   - Clave     : ark
echo   - Carpeta   : /roms/
echo.
echo Para abrir por Explorador de Windows: \\192.168.7.2\roms
echo.
goto :end

:failed
color 0c
echo [FALLO] No se detecto respuesta en 192.168.7.2.
echo.
echo Pasos de verificacion:
echo 1. Asegurate de conectar el cable USB-C entre tu PC y la consola.
echo 2. En la consola, ejecuta 'Enable_PC_Wired_Mode' desde Options - Tools.
echo 3. En Windows (ncpa.cpl), asegurate de haber asignado la IP estatica:
echo    - Direccion IP     : 192.168.7.1
echo    - Mascara de subred: 255.255.255.0
echo.

:end
pause
