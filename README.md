# luamake

## Install Instructions

### 1. Clone repo and submodules

```bash
git clone https://github.com/actboy168/luamake
cd luamake
git submodule update --init
```

### 2. Install:

#### Windows (msvc):
```
compile/install.bat
```

#### Linux / MacOS / Android / NetBSD / FreeBSD / OpenBSD / Windows (mingw)

[Install Ninja](https://github.com/ninja-build/ninja/wiki/Pre-built-Ninja-packages)

```
compile/install.sh
```

## Useful Build Commands

compile
```
compile/build.bat(msvc)
compile/build.sh (other)
```

compile and skip test
```
compile/build.bat notest(msvc)
compile/build.sh notest(other)
```

clean
```
compile/build.bat -t clean(msvc)
compile/build.sh -t clean(other)
```

## Quick Start

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

## Commands

> luamake

Build your project.

> luamake clean

Clean build output.

> luamake rebuild

Equivalent to `luamake clean && luamake`

> luamake lua [lua filename]

Run lua file.

> luamake test

Equivalent to `luamake lua test.lua`
