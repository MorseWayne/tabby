@echo off
setlocal

pushd "%~dp0"

set "ARCH=x64"
set "GYP_MSVS_VERSION=2022"
set "npm_config_msvs_version=2022"
set "APP_DIR=%~dp0dist\win-unpacked"
set "APP=%APP_DIR%\Tabby.exe"

echo ==^> Install dependencies
call yarn --network-timeout 1000000 --arch=%ARCH% --target-arch=%ARCH%
if errorlevel 1 goto failed

echo.
echo ==^> Build app and packages
call yarn run build --arch=%ARCH% --target_arch=%ARCH%
if errorlevel 1 goto failed

echo.
echo ==^> Prepackage builtin plugins
call node scripts\prepackage-plugins.mjs
if errorlevel 1 goto failed

echo.
echo ==^> Build unpacked app
call node_modules\.bin\electron-builder.cmd --win dir --x64
if errorlevel 1 goto failed

if not exist "%APP%" (
    echo Not found: %APP%
    goto failed
)

if not exist "%APP_DIR%\data" (
    mkdir "%APP_DIR%\data"
)

echo.
echo ==^> Run portable app
start "" "%APP%"

popd
exit /b 0

:failed
echo.
echo Build or run failed.
popd
exit /b 1
