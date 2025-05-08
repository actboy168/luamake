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

* Install Visual Studio

```
compile/install.bat
```

#### Linux / MacOS / Android / NetBSD / FreeBSD / OpenBSD / Windows (mingw)

* Install gcc, g++, ninja

```
compile/install.sh
```
or
```
sudo -s compile/install.sh
```

### 3. Useful Build Commands

compile
```
msvc > compile/build.bat
other> compile/build.sh
```

compile and skip test
```
msvc > compile/build.bat notest
other> compile/build.sh notest
```

clean
```
msvc > compile/build.bat -t clean
other> compile/build.sh -t clean
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
