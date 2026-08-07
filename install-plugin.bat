@echo off
setlocal EnableExtensions EnableDelayedExpansion

echo ============================================
echo  MohoMCP Plugin Installer (Windows)
echo ============================================
echo.

set "PACKAGE_ROOT=%~dp0moho-plugin"
set "MENU_SRC=%PACKAGE_ROOT%\Menu\MohoMCP"
set "MODULE_SRC=%PACKAGE_ROOT%\Modules\MohoMCP"

if not "%~1"=="" set "MOHO_CONTENT_DIR=%~1"

if not defined MOHO_CONTENT_DIR (
  if exist "%USERPROFILE%\Documents\Moho\Moho Pro" set "MOHO_CONTENT_DIR=%USERPROFILE%\Documents\Moho\Moho Pro"
)
if not defined MOHO_CONTENT_DIR (
  if exist "%USERPROFILE%\Documents\moho\Moho Pro" set "MOHO_CONTENT_DIR=%USERPROFILE%\Documents\moho\Moho Pro"
)

if not defined MOHO_CONTENT_DIR goto :missing_content
if not exist "%MOHO_CONTENT_DIR%" goto :missing_content

set "SCRIPTS_DIR=%MOHO_CONTENT_DIR%\Scripts"
set "DEST=%SCRIPTS_DIR%\Menu\MohoMCP"
set "MODULE_DEST=%SCRIPTS_DIR%\Modules\MohoMCP"

echo Using Moho Custom Content: %MOHO_CONTENT_DIR%
echo Installing menu entry to: %DEST%
echo Installing runtime modules to: %MODULE_DEST%
echo.

if not exist "%DEST%" mkdir "%DEST%"
if not exist "%MODULE_DEST%" mkdir "%MODULE_DEST%"

xcopy "%MENU_SRC%\*" "%DEST%\" /E /I /Y /Q >NUL
if errorlevel 1 goto :copy_failed
xcopy "%MODULE_SRC%\*" "%MODULE_DEST%\" /E /I /Y /Q >NUL
if errorlevel 1 goto :copy_failed

rem Remove the pre-0.2 layout that exposed support files as menu commands.
if exist "%DEST%\json.lua" del /Q "%DEST%\json.lua"
if exist "%DEST%\moho_mcp" rmdir /S /Q "%DEST%\moho_mcp"

rem Remove the obsolete selected-tool poller from older releases.
if exist "%SCRIPTS_DIR%\Tool\MohoMCP_Poller.lua" del /Q "%SCRIPTS_DIR%\Tool\MohoMCP_Poller.lua"
set "TOOL_LIST=%SCRIPTS_DIR%\Tool\_tool_list.txt"
if exist "%TOOL_LIST%" (
  set "TEMP_TOOL_LIST=%TEMP%\moho_mcp_tools_%RANDOM%.txt"
  findstr /V /C:"MohoMCP_Poller" "%TOOL_LIST%" > "!TEMP_TOOL_LIST!"
  move /Y "!TEMP_TOOL_LIST!" "%TOOL_LIST%" >NUL 2>&1
)

echo Installed files:
dir /S /B "%DEST%" "%MODULE_DEST%"
echo.
echo ============================================
echo  Installation complete
echo ============================================
echo.
echo Next steps:
echo   1. Restart Moho after the first install or a menu-entry change
echo   2. Choose Scripts ^> MohoMCP ^> Start/Stop MohoMCP Server
echo   3. For runtime Lua edits: stop, rerun this installer, then start again
echo   4. Start the MCP client; no polling tool is required
exit /B 0

:missing_content
echo ERROR: Moho's Custom Content folder could not be found.
echo.
echo In Moho, choose File ^> Open Custom Content Folder, then run:
echo   install-plugin.bat "C:\path\to\Moho Pro"
exit /B 1

:copy_failed
echo ERROR: Failed to copy the plugin into Moho Custom Content.
exit /B 1
