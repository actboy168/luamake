for /F %%A in ('type "%InstallDir%\VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt"') do (
    set "VCToolsVersion=%%A"
)
exit /B 0
