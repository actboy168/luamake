chcp 65001
luamake init -prebuilt -builddir build/msvc  -hostos windows
luamake init -prebuilt -builddir build/mingw -hostos windows -compiler gcc
luamake init -prebuilt -builddir build/linux -hostos linux
luamake init -prebuilt -builddir build/macos -hostos macos

if not exist compile\ninja (
	md compile\ninja
)
copy /Y build\msvc\make.ninja  compile\ninja\msvc.ninja
copy /Y build\mingw\make.ninja compile\ninja\mingw.ninja
copy /Y build\linux\make.ninja compile\ninja\linux.ninja
copy /Y build\macos\make.ninja compile\ninja\macos.ninja
