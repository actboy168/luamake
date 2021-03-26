@echo off
for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
  set InstallDir=%%i
)
call "%InstallDir%\Common7\Tools\vsdevcmd.bat" -arch=x86 -host_arch=x64 1>nul
call compile\generate_msvc_deps_prefix.bat
@echo on

ninja -f build\msvc\compile.ninja
