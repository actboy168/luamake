@echo off
chcp 65001 1>nul
if not exist compile\ninja (
	md compile\ninja
)

for %%a in (msvc mingw linux macos android) do (
	if "%%a" == "msvc" (
		luamake init -prebuilt -builddir build/msvc -hostos windows
	) else if "%%a" == "mingw" (
		luamake init -prebuilt -builddir build/mingw -hostos windows -hostshell sh
	) else (
		luamake init -prebuilt -builddir build/%%a -hostos %%a
	)
	copy /Y build\%%a\build.ninja compile\ninja\%%a.ninja 1>nul
	echo Copied %%a.ninja
)
