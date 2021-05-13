luamake init -prebuilt -builddir build/msvc  -hostos windows
luamake init -prebuilt -builddir build/mingw -hostos windows -compiler gcc
luamake init -prebuilt -builddir build/linux -hostos linux
luamake init -prebuilt -builddir build/macos -hostos macos

cp -afv build/msvc/make.ninja  compile/ninja/msvc.ninja
cp -afv build/mingw/make.ninja compile/ninja/mingw.ninja
cp -afv build/linux/make.ninja compile/ninja/linux.ninja
cp -afv build/macos/make.ninja compile/ninja/macos.ninja
