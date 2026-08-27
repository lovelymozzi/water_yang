@echo off
setlocal

set "PORT=8080"
set "PROJECT_ROOT=%~dp0."

echo [1/4] Closing any process that is listening on port %PORT%...
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":%PORT% .*LISTENING"') do (
    taskkill /PID %%P /F >nul 2>&1
)

where node >nul 2>&1
if errorlevel 1 (
    echo Node.js was not found. UI image path check cannot run.
    pause
    exit /b 1
)

echo [2/4] Checking UI image paths...
node "%PROJECT_ROOT%\tests\ui_bare_asset_paths_check.mjs"
if errorlevel 1 (
    echo UI image path check failed. Fix ui-editor paths or missing assets before running.
    pause
    exit /b 1
)

where py >nul 2>&1
if not errorlevel 1 (
    set "PYTHON=py -3"
) else (
    where python >nul 2>&1
    if errorlevel 1 (
        echo Python was not found. Install Python or add it to PATH.
        pause
        exit /b 1
    )
    set "PYTHON=python"
)

echo [3/4] Starting the server from:
echo %PROJECT_ROOT%
echo [4/4] Opening http://localhost:%PORT%/web/

start "Web Server (port %PORT%)" /D "%PROJECT_ROOT%" cmd.exe /k "%PYTHON% -m http.server %PORT%"
start "" "http://localhost:%PORT%/web/"

endlocal
