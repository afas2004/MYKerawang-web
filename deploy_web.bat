@echo off
cd /d "%~dp0"

echo ============================================
echo  MYKerawang - Build and deploy to Firebase
echo ============================================
echo.

REM Unique stamp per deploy. Compiled into the app (BUILD_ID) and written to
REM build\web\build.json; the app polls that file and offers "Update" when
REM they differ (lib/services/update_service.dart).
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMddHHmm"') do set BUILD_ID=%%i

echo [1/2] Building release web bundle (wasm), build %BUILD_ID%...
REM --wasm adds the skwasm renderer with an automatic canvaskit fallback.
REM Required for iOS: plain "flutter build web" leaves iOS WebKit on a white
REM screen. (--web-renderer html no longer exists in current Flutter.)
REM --pwa-strategy=none replaces Flutter's offline-first service worker, which
REM served cached (stale) app code to returning phones after every deploy.
call flutter build web --release --wasm --pwa-strategy=none --dart-define=BUILD_ID=%BUILD_ID%
if errorlevel 1 goto :error
> build\web\build.json echo {"build_id":"%BUILD_ID%"}
REM Version the app-code URLs (see web/flutter_bootstrap.js). UTF-8 without BOM.
powershell -NoProfile -Command "$f='build\web\index.html'; [IO.File]::WriteAllText($f, [IO.File]::ReadAllText($f).Replace('__BUILD_ID__','%BUILD_ID%'))"
if errorlevel 1 goto :error
REM Same stamp in the standalone bootstrap (index.html inlines it, but keep
REM the file consistent for anything that requests it directly).
powershell -NoProfile -Command "$f='build\web\flutter_bootstrap.js'; [IO.File]::WriteAllText($f, [IO.File]::ReadAllText($f).Replace('__BUILD_ID__','%BUILD_ID%'))"
if errorlevel 1 goto :error
REM Self-removing worker: frees phones still running the old offline cache.
copy /y build\web\sw_reset.js build\web\flutter_service_worker.js > nul

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
echo   * Open users get an "Update" prompt within
echo     15 minutes (or Settings - Check for updates).
echo ============================================
goto :eof

:error
echo.
echo Failed - scroll up for the error, paste it to Claude.
pause
