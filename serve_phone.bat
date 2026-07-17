@echo off
cd /d "%~dp0"

echo ============================================
echo  MYKerawang - Serve to phone over Wi-Fi
echo ============================================
echo.

echo [1/3] Building release web bundle (takes a minute)...
call flutter build web --release
if errorlevel 1 goto :error

echo.
echo [2/3] Installing Dart static server (dhttpd, one-time)...
call dart pub global activate dhttpd
if errorlevel 1 goto :error

echo.
echo [3/3] Finding your Wi-Fi IPv4 address...
set IP=
for /f "tokens=2 delims=:" %%a in ('netsh interface ip show address "Wi-Fi" ^| findstr /c:"IP Address"') do set IP=%%a
if defined IP set IP=%IP: =%
if not defined IP set IP=CHECK-IPCONFIG-MANUALLY

echo.
echo ============================================
echo   ON YOUR PHONE (same Wi-Fi as this PC):
echo.
echo       http://%IP%:8080
echo.
echo ============================================
echo   * If Windows Firewall pops up: click ALLOW
echo     (check "Private networks")
echo   * Campus Wi-Fi blocking it? Use your phone's
echo     hotspot, connect this PC to it, re-run this.
echo   * Login broken? Add the URL above to Supabase
echo     Auth - Redirect URLs.
echo   * Press Ctrl+C to stop the server.
echo ============================================
echo.
call dart pub global run dhttpd --path build/web --host 0.0.0.0 --port 8080
goto :eof

:error
echo.
echo Build failed - scroll up for the error, paste it to Claude.
pause
