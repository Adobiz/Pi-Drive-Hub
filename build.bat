@echo off
REM ============================================================
REM  PI Netdisk - one-click release build script
REM  Usage:
REM    build.bat              build release (Chinese, default)
REM    build.bat en           build release (English)
REM    build.bat clean        clean build dir then build release (Chinese)
REM    build.bat clean en     clean then build release (English)
REM  Only release builds are supported (debug stripped for release
REM  quality). Language is chosen at build time via
REM  --dart-define=APP_LANG.
REM ============================================================
setlocal enabledelayedexpansion
cd /d "%~dp0"

set MODE=%1
set LANG_ARG=%2
if "%MODE%"=="" set MODE=release
if "%LANG_ARG%"=="" set LANG_ARG=zh

REM ---- normalize: "build.bat en" means mode=release lang=en ----
if "%MODE%"=="en" (
    set MODE=release
    set LANG_ARG=en
)
REM ---- reject debug ----
if "%MODE%"=="debug" (
    echo [ERROR] debug builds are not supported.
    echo         Use plain "build.bat" for release.
    exit /b 1
)

set DART_DEFINE=APP_LANG=%LANG_ARG%
if "%LANG_ARG%"=="zh" set DART_DEFINE=
echo [INFO] mode=%MODE% lang=%LANG_ARG%

REM ---------- 0. check flutter ----------
where flutter >nul 2>nul
if errorlevel 1 (
    echo [ERROR] flutter not found. Install it and add to PATH.
    exit /b 1
)

REM ---------- 1. check nuget (flutter_inappwebview_windows build dep) ----------
where nuget >nul 2>nul
if errorlevel 1 (
    echo [WARN] nuget.exe not found in PATH.
    echo        flutter_inappwebview_windows needs it to download WebView2 deps.
    echo        Install it, or add its folder to PATH, then rerun.
    echo        (e.g. setx PATH "%%PATH%%;C:\tools")
)

REM ---------- 2. kill old instance (avoid LNK1168) ----------
taskkill /F /IM pi_pan.exe >nul 2>nul

REM ---------- 3. pub get ----------
echo [1/5] flutter pub get ...
call flutter pub get
if errorlevel 1 (
    echo [ERROR] pub get failed
    exit /b 1
)

REM ---------- 4. analyze ----------
echo [2/5] flutter analyze ...
call flutter analyze
if errorlevel 1 (
    echo [WARN] analyze has issues. Set SKIP_CHECK=1 to force build.
    if not "%SKIP_CHECK%"=="1" (
        exit /b 1
    )
)

REM ---------- 5. clean / build ----------
if "%MODE%"=="clean" (
    echo [3/5] cleaning build dir ...
    if exist build rmdir /s /q build
    set MODE=release
)

echo [3/5] flutter build windows --release %DART_DEFINE% ...
if "%DART_DEFINE%"=="" (
    call flutter build windows --release
) else (
    call flutter build windows --release --dart-define=%DART_DEFINE%
)
if errorlevel 1 (
    echo [ERROR] build failed
    exit /b 1
)

echo.
echo ============================================================
echo  BUILD OK!  lang=%LANG_ARG% mode=release
echo  Output: build\windows\x64\runner\Release\pi_pan.exe
echo ============================================================
echo.
echo NOTE: to distribute, copy the exe together with the
echo       build\windows\x64\runner\Release\data folder.
endlocal
