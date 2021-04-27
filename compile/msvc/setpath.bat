SET setpath=%cd%
echo %path%|findstr /i %setpath% 1>nul && (goto END) 
set "path=%setpath%;%path%"
reg add "HKEY_CURRENT_USER\Environment" /v "Path" /t REG_EXPAND_SZ /d "%PATH%" /f 1>nul
refreshenv
:END
