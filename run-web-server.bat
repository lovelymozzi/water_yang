@echo off
setlocal

set "PORT=8080"
set "PROJECT_ROOT=%~dp0."

echo [1/3] Closing any process that is listening on port %PORT%...
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":%PORT% .*LISTENING"') do (
    taskkill /PID %%P /F >nul 2>&1
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

echo [2/3] Starting the server from:
echo %PROJECT_ROOT%
echo [3/3] Opening http://localhost:%PORT%/web/

start "Web Server (port %PORT%)" /D "%PROJECT_ROOT%" cmd.exe /k "%PYTHON% -m http.server %PORT%"
start "" "http://localhost:%PORT%/web/"

endlocal
