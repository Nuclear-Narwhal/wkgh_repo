@echo off
echo Copying registration script...
mkdir C:\Autopilot 2>nul
copy /Y "%~dp0register.ps1" C:\Autopilot\register.ps1 >nul

if %errorlevel% neq 0 (
    echo.
    echo ERROR: Could not copy register.ps1 from USB.
    echo Make sure register.ps1 is in the same folder as go.cmd.
    pause
    exit /b 1
)

echo.
echo ============================================
echo  USB safe to unplug now.
echo  Device will reboot itself when done.
echo ============================================
echo.
echo Starting registration in background...
start "Autopilot Registration" powershell -ExecutionPolicy Bypass -File C:\Autopilot\register.ps1
echo Done. Move to next device.
timeout /t 3 > nul
exit