chcp 65001
luamake init -rebuilt no -plat msvc
luamake init -rebuilt no -plat mingw
luamake init -rebuilt no -plat linux
luamake init -rebuilt no -plat macos

if not exist ninja (
	md ninja
)
copy /Y build\msvc\make.ninja  ninja\msvc.ninja
copy /Y build\mingw\make.ninja ninja\mingw.ninja
copy /Y build\linux\make.ninja ninja\linux.ninja
copy /Y build\macos\make.ninja ninja\macos.ninja
