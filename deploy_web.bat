@echo off
cd /d "%~dp0"

echo ============================================
echo  MYKerawang - Build and deploy to Firebase
echo ============================================
echo.

echo [1/2] Building release web bundle (wasm)...
REM --wasm adds the skwasm renderer with an automatic canvaskit fallback.
REM Required for iOS: plain "flutter build web" leaves iOS WebKit on a white
REM screen. (--web-renderer html no longer exists in current Flutter.)
call flutter build web --release --wasm
if errorlevel 1 goto :error

echo.
echo [2/2] Deploying to Firebase Hosting...
call firebase deploy --only hosting
if errorlevel 1 goto :error

echo.
echo ============================================
echo  Done. Your app is live at the Hosting URL
echo  printed above (https://<project>.web.app).
echo.
echo  Reminders:
echo   * Add that URL to Supabase Auth - Redirect URLs
echo     (and Site URL) or Google login will fail.
echo   * Hard-refresh (Ctrl+Shift+R) to bypass the
echo     old service worker after each deploy.
echo ============================================
goto :eof

:error
echo.
echo Failed - scroll up for the error, paste it to Claude.
pause
