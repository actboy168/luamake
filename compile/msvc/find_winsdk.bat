@echo off

call :GetWin10SDKVersion HKLM\SOFTWARE\Wow6432Node
if errorlevel 1 call :GetWin10SDKVersion HKCU\SOFTWARE\Wow6432Node
if errorlevel 1 call :GetWin10SDKVersion HKLM\SOFTWARE
if errorlevel 1 call :GetWin10SDKVersion HKCU\SOFTWARE
if errorlevel 1 exit /B 1
exit /B 0

:GetWin10SDKVersion
for /F "tokens=1,2*" %%i in ('reg query "%1\Microsoft\Microsoft SDKs\Windows\v10.0" /v "InstallationFolder"') do (
    if "%%i"=="InstallationFolder" (
        set WindowsSdkDir=%%~k
    )
)

setlocal enableDelayedExpansion
if not "%WindowsSdkDir%"=="" for /f %%i IN ('dir "%WindowsSdkDir%include\" /b /ad-h /on') DO (
    if exist "%WindowsSdkDir%include\%%i\um\winsdkver.h" (
        set result=%%i
        if "!result:~0,3!"=="10." (
            set SDK=!result!
        )
    )
)
endlocal & set WindowsSDKVersion=%SDK%
exit /B 0
