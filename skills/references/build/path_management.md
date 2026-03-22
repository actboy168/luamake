# 路径管理

## workdir 与 rootdir

- **workdir**：当前构建脚本的工作目录。所有相对路径（如 `sources`、`includes`）都基于 workdir 解析。
- **rootdir**：目标属性中可手动指定的根目录，用于覆盖默认的路径解析基准。

主构建脚本的 workdir 默认为项目根目录（即运行 `luamake` 的目录）。

## require vs lm:import

两者都可以加载其他 Lua 构建脚本，但行为有显著区别：

| 特性 | `require` | `lm:import` |
|------|-----------|-------------|
| workdir | **不变**，保持调用者的 workdir | **切换**到被导入文件所在目录 |
| 沙盒 | 共享当前环境的 `package.loaded` | 创建新的沙盒子 workspace |
| 属性继承 | 直接共享同一个 `lm` 对象 | 子 workspace 可读取父级属性，但修改不影响父级 |
| 路径格式 | Lua 模块格式：`"subdir.make"` | 文件路径格式：`"subdir/make.lua"` |
| 重复加载 | 仅加载一次（`package.loaded` 缓存） | 仅加载一次（内部 visited 缓存） |
| 适用场景 | 同目录下的模块拆分、工具函数 | 子目录/子项目的独立构建脚本 |

### require —— 同目录模块加载

```lua
-- 项目结构：
-- project/
-- ├── make.lua
-- ├── compile/
-- │   ├── common.lua    -- require "compile.common"
-- │   └── lua.lua       -- require "compile.lua"

local lm = require "luamake"
require "compile.common"   -- workdir 不变，仍然是 project/
require "compile.lua"      -- 共享同一个 lm 对象
```

`require` 在 sandbox 中的搜索路径为 `?.lua;?/init.lua`，基于当前 sandbox 的 rootdir 解析文件路径。由于 workdir 不变，所有 `sources`、`includes` 等路径仍然相对于原始工作目录。

### lm:import —— 子目录独立构建

```lua
-- 项目结构：
-- project/
-- ├── make.lua
-- └── bee.lua/
--     ├── make.lua       -- lm:import "bee.lua/make.lua"
--     └── 3rd/
--         └── lua54/

-- project/make.lua
local lm = require "luamake"
lm:import "bee.lua/make.lua"
-- bee.lua/make.lua 中的 workdir 自动切换为 project/bee.lua/
-- 其中的 sources = "bee/**/*.cpp" 会解析为 bee.lua/bee/**/*.cpp
```

`lm:import` 的关键行为：
1. 将路径解析为绝对路径，提取目录作为新的 **rootdir/workdir**
2. 创建子 workspace，继承父级全局属性（如 `cxx`、`mode`），但子级的修改不会回传
3. 被导入脚本中的相对路径都基于新的 workdir 解析

## rootdir 边界约束

构建目标中所有通过 glob 解析的路径（如 `sources`、`inputs`）**不能引用 rootdir 之外的文件**。如果路径以 `../` 开头，尝试访问上级目录，luamake 会直接报错：

```
FATAL: Not supported that source files outside the rootdir: ../some/file.cpp
```

这意味着以下写法是**非法**的：

```lua
lm:exe "app" {
    sources = "../other_project/src/*.cpp",   -- ❌ 错误：不能用 ../ 引用 rootdir 之外的文件
    includes = "../../shared/include",        -- ❌ 错误：同样不能用 ../ 引用外部目录
}
```

### 为什么有这个限制？

Ninja 构建系统要求所有源文件路径可被稳定追踪以实现增量构建。允许任意 `../` 路径会导致路径解析不确定、构建缓存失效等问题。rootdir 作为路径解析的边界，确保了构建的可靠性和可复现性。

### 如何引用外部文件？

如果确实需要引用 rootdir 之外的文件，可以通过以下方式解决：

1. **调整 rootdir**：将 `rootdir` 设置为更高层级的目录，使外部文件落入范围内

```lua
lm:exe "app" {
    rootdir = "..",                           -- 将 rootdir 提升一级
    sources = "other_project/src/*.cpp",      -- 现在路径在 rootdir 内了
    includes = "../shared/include",
}
```

2. **使用 lm:import**：如果外部文件属于另一个子项目，用 `lm:import` 将其作为独立子项目导入，让它在自己的 rootdir 内构建

```lua
lm:import "../other_project/make.lua"     -- other_project 在自己的 rootdir 内构建
lm:exe "app" {
    deps = "other_lib",                       -- 依赖导入的目标
    sources = "src/*.cpp",
}
```

3. **使用 lm:path**：将外部路径转为绝对路径对象，绕过相对路径的限制

## lm:path —— 创建绝对路径

`lm:path(value)` 基于当前 workdir 将相对路径转换为**绝对路径对象（LmPath）**。当需要在不同 workdir 之间传递路径时非常有用。

```lua
-- bee.lua/compile/common.lua（workdir 为 bee.lua/）
local lm = require "luamake"

-- 将 "3rd/lua55" 转换为绝对路径，后续无论 workdir 如何变化都能正确引用
lm.luadir = lm:path("3rd/lua"..lm.lua)

lm:source_set "source_lua" {
    includes = lm.luadir,              -- 即使在其他 workdir 中使用也能正确解析
    sources = { lm.luadir / "onelua.c" },  -- LmPath 支持 / 操作符拼接路径
}
```

### 为什么需要 lm:path？

在使用 `lm:import` 导入子目录脚本时，子脚本的 workdir 会变化。如果子脚本设置了一个普通字符串路径作为全局属性（如 `lm.luadir = "3rd/lua55"`），当父级或其他子 workspace 引用这个属性时，相对路径会基于它们自己的 workdir 解析，导致路径错误。

`lm:path` 解决了这个问题——它在设置时就将路径转为绝对路径，后续无论在哪个 workdir 下使用都能正确定位。

## 典型的多目录项目结构

```lua
-- project/
-- ├── make.lua
-- ├── src/
-- │   └── main.cpp
-- ├── libs/
-- │   ├── make.lua      -- 独立子构建
-- │   └── lib.cpp
-- └── compile/
--     └── common.lua    -- 共享配置模块

-- project/make.lua
local lm = require "luamake"
require "compile.common"       -- 加载共享配置，workdir 不变
lm:import "libs/make.lua"     -- 导入子项目，workdir 切换到 libs/

lm:exe "app" {
    deps = "mylib",            -- 引用 libs/make.lua 中定义的目标
    sources = "src/main.cpp",  -- 相对于 project/
}

-- project/libs/make.lua
local lm = require "luamake"
lm:lib "mylib" {
    sources = "lib.cpp",       -- 相对于 libs/（因为 import 切换了 workdir）
}
```
