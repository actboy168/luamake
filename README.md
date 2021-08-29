# luamake

## Build

```bash
git clone https://github.com/actboy168/luamake
cd luamake
git submodule update --init
```

msvc
* compile/install.bat

mingw / macos / linux / android

* Install ninja
* compile/install.sh

## Quick start

Create file `make.lua`. For example, this is a `make.lua` to compile lua:
``` lua
local lm = require "luamake"
lm:exe "lua" {
    sources = {
        "src/*.c",
        "!src/luac.c" -- ignore luac.c
    }
}
```

Build
``` bash
$ luamake
```

Run
``` bash
$ ./build/bin/lua
```
