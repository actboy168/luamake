luamake init -prebuilt -builddir build/msvc  -os windows
luamake init -prebuilt -builddir build/mingw -os windows -compiler gcc
luamake init -prebuilt -builddir build/linux -os linux
luamake init -prebuilt -builddir build/macos -os macos

cp -afv build/msvc/make.ninja  compile/ninja/msvc.ninja
cp -afv build/mingw/make.ninja compile/ninja/mingw.ninja
cp -afv build/linux/make.ninja compile/ninja/linux.ninja
cp -afv build/macos/make.ninja compile/ninja/macos.ninja
