chcp 65001
luamake init -rebuilt no -builddir build/msvc  -os windows
luamake init -rebuilt no -builddir build/mingw -os windows -compiler gcc
luamake init -rebuilt no -builddir build/linux -os linux
luamake init -rebuilt no -builddir build/macos -os macos

if not exist compile\ninja (
	md compile\ninja
)
copy /Y build\msvc\make.ninja  compile\ninja\msvc.ninja
copy /Y build\mingw\make.ninja compile\ninja\mingw.ninja
copy /Y build\linux\make.ninja compile\ninja\linux.ninja
copy /Y build\macos\make.ninja compile\ninja\macos.ninja
