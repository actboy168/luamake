luamake init -prebuilt -builddir build/msvc  -hostos windows
luamake init -prebuilt -builddir build/mingw -hostos windows -hostshell sh
luamake init -prebuilt -builddir build/linux -hostos linux
luamake init -prebuilt -builddir build/macos -hostos macos
luamake init -prebuilt -builddir build/android -hostos android

cp -afv build/msvc/build.ninja  compile/ninja/msvc.ninja
cp -afv build/mingw/build.ninja compile/ninja/mingw.ninja
cp -afv build/linux/build.ninja compile/ninja/linux.ninja
cp -afv build/macos/build.ninja compile/ninja/macos.ninja
cp -afv build/android/build.ninja compile/ninja/android.ninja
