IF /I %PROCESSOR_ARCHITECTURE% == AMD64 GOTO AMD64
IF DEFINED PROCESSOR_ARCHITEW6432 GOTO AMD64
SET ARCH=x86
GOTO END
:AMD64
SET ProgramFiles=%ProgramFiles(x86)%
SET ARCH=x64
:END

FOR /f "usebackq tokens=*" %%i in (`"%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
  SET InstallDir=%%i
)
CALL compile\msvc\find_winsdk.bat
SET VSCMD_SKIP_SENDTELEMETRY=1
CALL "%InstallDir%\Common7\Tools\vsdevcmd.bat" -arch=%ARCH% -host_arch=%ARCH% -winsdk=%WindowsSDKVersion% 1>nul
