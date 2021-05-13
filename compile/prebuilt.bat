chcp 65001
luamake init -prebuilt -builddir build/msvc  -hostos windows
luamake init -prebuilt -builddir build/mingw -hostos windows -compiler gcc
luamake init -prebuilt -builddir build/linux -hostos linux
luamake init -prebuilt -builddir build/macos -hostos macos

if not exist compile\ninja (
	md compile\ninja
)
copy /Y build\msvc\build.ninja  compile\ninja\msvc.ninja
copy /Y build\mingw\build.ninja compile\ninja\mingw.ninja
copy /Y build\linux\build.ninja compile\ninja\linux.ninja
copy /Y build\macos\build.ninja compile\ninja\macos.ninja
