IF NOT "%VCToolsVersion%" == "" GOTO QUIT

IF /I "%PROCESSOR_ARCHITECTURE%" == "AMD64" GOTO AMD64
IF /I "%PROCESSOR_ARCHITECTURE%" == "ARM64" GOTO ARM64
IF DEFINED PROCESSOR_ARCHITEW6432 GOTO AMD64
SET HOST_ARCH=x86
SET ARCH=x86
GOTO END
:AMD64
SET ProgramFiles=%ProgramFiles(x86)%
SET HOST_ARCH=x64
SET ARCH=x64
GOTO END
:ARM64
SET HOST_ARCH=x64
SET ARCH=arm64
:END

FOR /f "usebackq tokens=*" %%i in (`"%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -prerelease -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
  SET InstallDir=%%i
)
IF "%InstallDir%" == "" echo "Can not find msvc." && exit 1

CALL compile\msvc\find_toolset.bat
CALL compile\msvc\find_winsdk.bat
SET VSCMD_SKIP_SENDTELEMETRY=1
CALL "%InstallDir%\Common7\Tools\vsdevcmd.bat" -arch=%ARCH% -host_arch=%HOST_ARCH% -winsdk=%WindowsSDKVersion% -vcvars_ver=%VCToolsVersion% 1>nul
:QUIT
