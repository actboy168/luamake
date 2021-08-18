SET setpath=%cd%
echo %path%|findstr /i %setpath% 1>nul && (goto END)
for /F "tokens=1,2*" %%i in ('reg query "HKCU\Environment" /v "Path"') do (
    if "%%i"=="Path" (
        set regpath=%%~k
    )
) 
set "path=%setpath%;%path%" 
set "regpath=%setpath%;%regpath%"
reg add "HKCU\Environment" /v "Path" /t REG_EXPAND_SZ /d "%regpath%" /f 1>nul
:END
