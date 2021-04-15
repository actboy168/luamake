chcp 65001
luamake init -rebuilt no -plat msvc
luamake init -rebuilt no -plat mingw
luamake init -rebuilt no -plat linux
luamake init -rebuilt no -plat macos

if not exist compile\ninja (
	md compile\ninja
)
copy /Y build\msvc\make.ninja  compile\ninja\msvc.ninja
copy /Y build\mingw\make.ninja compile\ninja\mingw.ninja
copy /Y build\linux\make.ninja compile\ninja\linux.ninja
copy /Y build\macos\make.ninja compile\ninja\macos.ninja
