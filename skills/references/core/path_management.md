# 路径管理

luamake 的路径系统是构建脚本中的核心概念。理解 `workdir`、`rootdir` 的关系，以及 `require` 与 `import` 的区别，是正确编写多目录项目的关键。

---

## workdir 与 rootdir

| 概念 | 说明 | 默认值 |
|------|------|--------|
| `workdir` | 当前工作区的基准目录，影响路径解析。由 `lm:import` 自动设置 | 项目根目录 |
| `rootdir` | 目标的源文件搜索根目录，影响 `sources` glob 和 `includes` 等路径的解析 | `"."` (相对于 workdir) |

### workdir 的传播

`workdir` 由 `lm:import` 自动管理。当 import 一个子目录的 `make.lua` 时，`workdir` 自动切换到该文件所在目录：

```
project/
├── make.lua          # workdir = "project/"
├── src/
│   └── make.lua      # workdir = "project/src/"（由 import 自动设置）
└── 3rd/
    └── lib/
        └── make.lua  # workdir = "project/3rd/lib/"
```

```lua
-- project/make.lua
local lm = require "luamake"

lm:import "src/make.lua"       -- 子脚本的 workdir 变为 project/src/
lm:import "3rd/lib/make.lua"   -- 子脚本的 workdir 变为 project/3rd/lib/
```

### rootdir 的使用

`rootdir` 用于改变目标中源文件路径的解析基准。在子脚本中，如果源文件不在 workdir 下，可以通过 `rootdir` 指定：

```lua
-- 假设 workdir 为 project/src/
lm:exe "myapp" {
    rootdir = "../",              -- 源文件相对于 project/ 解析
    sources = "src/main.cpp",     -- 实际路径：project/src/main.cpp
    includes = "include",         -- 实际路径：project/include
}
```

---

## require 与 import 的区别

### lm:import

`import` 是 luamake 特有的子脚本加载方式，与 Lua 标准的 `require` 有本质区别：

| 特性 | `lm:import` | `require` |
|------|------------|-----------|
| 路径基准 | 相对于当前 workdir | 按 Lua 模块搜索路径 |
| 沙箱隔离 | ✅ 子脚本在沙箱中运行 | ❌ 共享全局环境 |
| workdir | ✅ 自动切换到文件所在目录 | ❌ 不改变 workdir |
| 属性继承 | ✅ 子脚本可读取父脚本的属性，但修改不影响父脚本 | — |
| 重复加载 | ❌ 同一路径只加载一次 | ✅ 受 `package.loaded` 缓存控制 |
| 用途 | 加载子项目构建脚本 | 加载 Lua 通用模块 |

```lua
-- 推荐：用 import 加载子项目的构建脚本
lm:import "subproject/make.lua"

-- 推荐：用 require 加载工具模块
local utils = require "build_utils"
```

### import 的沙箱机制

子脚本通过 `import` 加载时运行在沙箱中：
- 可以**读取**父脚本设置的属性（如全局 `lm:conf` 配置）
- 但**修改**属性不会反向影响父脚本
- `require` 的搜索路径包含 `?.lua`、`?/init.lua` 以及 luamake 内置库路径

---

## lm:path — 创建绝对路径

将一个相对路径转换为基于当前 workdir 的绝对路径对象。返回值可直接用于目标属性中。

```lua
local lm = require "luamake"

-- 创建绝对路径
local inc = lm:path "3rd/include"
local src = lm:path "src"

lm:exe "myapp" {
    includes = inc,
    sources = { src / "*.cpp" },    -- 路径对象支持 / 运算符
}
```

### 应用场景

`lm:path` 在需要跨 workdir 传递路径时非常有用：

```lua
-- project/make.lua
local lm = require "luamake"

-- 创建一个命名配置，包含绝对路径
lm:conf "mylib_conf" {
    includes = lm:path "3rd/mylib/include",   -- 绝对化，不受子脚本 workdir 影响
    defines = "USE_MYLIB",
}

lm:import "src/make.lua"
```

```lua
-- project/src/make.lua
local lm = require "luamake"

-- 即使 workdir 是 project/src/，也能正确找到 project/3rd/mylib/include
lm:exe "app" {
    confs = "mylib_conf",
    sources = "*.cpp",
}
```

---

## 路径中的变量引用

路径属性中可以使用 `$variable` 引用 Ninja 变量：

```lua
lm:exe "myapp" {
    sources = "src/*.cpp",
    includes = "$builddir/generated",   -- 引用构建目录
}
```

常用变量：

| 变量 | 说明 |
|------|------|
| `$builddir` | 构建目录（默认 `build`） |
| `$bin` / `$bindir` | 二进制输出目录 |
| `$obj` / `$objdir` | 对象文件目录 |

---

## args 属性中的 @ 语法

在 `lm:rule`、`lm:build`、`lm:runlua` 的 `args` 属性中，`@` 前缀会将路径展开为相对于 rootdir 的绝对路径：

```lua
lm:runlua "gen" {
    script = "tools/gen.lua",
    args = {
        "@templates/config.in",    -- 展开为绝对路径
        "$builddir/config.h",      -- Ninja 变量保持不变
    },
    outputs = "$builddir/config.h",
}
```

也支持 `@{path}` 内联语法，用于在字符串中嵌入路径：

```lua
lm:build "process" {
    args = { "tool", "--input=@{data/input.txt}", "--output=$out" },
    outputs = "$builddir/output.txt",
}
```
