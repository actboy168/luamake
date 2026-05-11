#!/usr/bin/env sh
set -e

DIR="$(cd "$(dirname "$0")"/.. || exit 1; pwd)"
cd "$DIR" || exit 1

# Generate lua_embed.c for standalone target
mkdir -p build
cat > build/embed_config.lua << 'EOF'
return {
    groups = {
        { name = "data", entries = {} },
        { name = "main", entries = { { file = "main.lua", name = "main.lua" } } },
        { name = "preload", lua_mode = true, entries = { { dir = "scripts", pattern = "?.lua;?/init.lua" } } },
    },
}
EOF
luamake lua scripts/lua_embed/lua_embed_gen.lua \
    build/embed_config.lua \
    compile/ninja/lua_embed.c

# Generate ninja files
luamake init -prebuilt -builddir build/msvc  -hostos windows "$@"
luamake init -prebuilt -builddir build/mingw -hostos windows -hostshell sh "$@"
luamake init -prebuilt -builddir build/linux -hostos linux "$@"
luamake init -prebuilt -builddir build/macos -hostos macos "$@"
luamake init -prebuilt -builddir build/android -hostos android "$@"
luamake init -prebuilt -builddir build/netbsd -hostos netbsd "$@"
luamake init -prebuilt -builddir build/freebsd -hostos freebsd "$@"
luamake init -prebuilt -builddir build/openbsd -hostos openbsd "$@"

cp -afv build/msvc/build.ninja  compile/ninja/msvc.ninja
cp -afv build/mingw/build.ninja compile/ninja/mingw.ninja
cp -afv build/linux/build.ninja compile/ninja/linux.ninja
cp -afv build/macos/build.ninja compile/ninja/macos.ninja
cp -afv build/android/build.ninja compile/ninja/android.ninja
cp -afv build/netbsd/build.ninja compile/ninja/netbsd.ninja
cp -afv build/freebsd/build.ninja compile/ninja/freebsd.ninja
cp -afv build/openbsd/build.ninja compile/ninja/openbsd.ninja
