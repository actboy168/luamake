# lm:lua_embed — Lua / 资源嵌入

`lm:lua_embed` 是一个高阶目标，用来把 Lua 脚本或任意二进制资源以 C 数组的方式嵌入到可执行文件。它在背后自动完成 **代码生成 → source_set → 依赖导出** 的完整管道，相比手写 `lm:runlua` + `objdeps` 更简洁、可靠。

本文档是 `lm:lua_embed` 的权威参考，集中阐述其所有规则与行为。`SKILL.md` / `bp_codegen.md` / `bp_dependency.md` / `advanced_api.md` 中的相关片段为摘要/示例，细节以本文档为准。

---

## 1. 目标产物与导出属性

一个 `lm:lua_embed "xxx" { ... }` 在内部登记为一个 `source_set`，会固定生成两个文件：

| 产物 | 路径 | 作用 |
|---|---|---|
| 生成的 C 源 | `$builddir/lua_embed/xxx/lua_embed.c` | 定义全局变量 `const lua_embed_bundle lua_embed` |
| 生成的 C 头 | `$builddir/lua_embed/xxx/lua_embed_data.h` | 声明 `lua_embed_entry` / `lua_embed_bundle`，`extern` 全局变量 |

并自动导出两个属性：

- `export_includes` → 上述目录，使 `#include "lua_embed_data.h"` 能找到；
- `export_objdeps`  → 聚合 `.c` 和 `.h` 两个产物的 phony，确保编译前源与头都已生成。

**依赖方只需 `deps = "xxx"`**，无需手动写 `includes` / `objdeps`。内部 phony 名（例如 `__lua_embed_gen_xxx__`）与内部路径为实现细节，**不要在用户脚本中硬编码**。

> 启用 `bee_glue = true` 时，会额外把 [scripts/lua_embed/bee_glue.c](../../../scripts/lua_embed/bee_glue.c) 也加入该 source_set 一起编译。

---

## 2. 配置骨架

```lua
lm:lua_embed "myembed" {
    bee_glue = true,              -- 可选：启用 bee 胶水层
    data = {
        <group1> = {              -- 组名必须是合法 C 标识符
            bytecode = true,      -- 可选：该组嵌入字节码而非源码
            -- 组的数组部分 = 条目列表，三种写法见 §3
            "src/foo.lua",
            { dir = "lualib" },
            { file = "assets/a.json", name = "a.json" },
        },
        <group2> = { ... },
    },
}
```

核心概念：

- 所有文件通过顶层 `data` 的 **组（group）** 组织，组名直接成为生成的 `lua_embed_bundle` 结构体的字段名；
- 组名必须匹配 `^[A-Za-z_][A-Za-z0-9_]*$`，否则代码生成阶段会报错；
- 组之间在结构体中按 **字母序** 排列（稳定，可用于代码静态分析）；
- `bytecode` 是 **每个组独立** 的开关，不是全局开关。

---

## 3. 组内条目：三种写法

组的数组部分逐项处理，允许混合三种写法：

### 3.1 裸字符串 —— 单文件，name 取文件名

```lua
"src/main.lua"   -- name = "main.lua"
```

### 3.2 `{ dir = ..., prefix = ..., pattern = ... }` —— 扫描目录

| 字段 | 必选 | 说明 |
|---|---|---|
| `dir`     | ✓ | 要递归扫描的目录（相对 `rootdir`） |
| `prefix`  | ✗ | 生成的 `name`（或模块名）前缀 |
| `pattern` | ✗ | 指定后启用 **Lua 模块名扫描**，见 §4 |

**扫描模式**由 §4 决定（原始文件名 / Lua 模块名）。

### 3.3 `{ file = ..., name = ... }` —— 单文件 + 显式命名

```lua
{ file = "scripts/config.lua", name = "config" }
```

`name` 必填；缺失会在 `write_config` 阶段 `assert` 失败。

---

## 4. `lua_mode`（Lua 模块名扫描）启用规则

每个组有两种扫描模式：

- **普通模式**：`dir` 条目按 **原始相对路径** 作为 `name`（例如 `sub/bar.lua`）；
- **lua_mode**：`dir` 条目按 **Lua 模块名** 作为 `name`（例如 `sub.bar`）。

触发 `lua_mode` 的条件（见 [lua_embed.lua](../../../scripts/lua_embed.lua) `group_lua_mode`）**任一满足即可**：

1. 组内任何一个 `dir` 条目带了 `pattern` 字段 → **整组** 切到 lua_mode；
2. `bee_glue = true` 且组名 = `preload` → 自动切到 lua_mode（因为 `_PRELOAD` 以模块名作键）；

其余情况走普通模式。

### 4.1 `pattern` 语法

格式同 Lua 的 `package.path`：用 `;` 分隔多个模板，每个模板用 `?` 作占位符。默认值为：

```
?.lua;?/init.lua
```

匹配规则（见 `match_pattern`）：
- `foo.lua` 命中 `?.lua`，模块名 `foo`；
- `foo/init.lua` 命中 `?/init.lua`，模块名 `foo`；
- `a/b.lua` 命中 `?.lua`，`a/b` → 内部 `/` 自动替换为 `.`，最终 `a.b`；
- 若设置了 `prefix = "pkg"`，则最终模块名为 `pkg.a.b`；
- 不匹配任何模板的 `.lua` 文件会被跳过并打印 `[lua_embed] warning: ... does not match any pattern, skipped`；
- 非 `.lua` 文件在 lua_mode 下直接忽略。

### 4.2 同模块名冲突处理

扫描过程中若同一模块名重复命中，采用 **确定性消歧策略**（见 `scan_lua_dir`）：

- **同一次 `scan_lua_dir` 调用内**（即同一 `{ dir, pattern }`）：按 `pattern` 的左到右优先级决定胜者，对齐 Lua `package.path` 的 `?.lua` 优先于 `?/init.lua` 的语义；新胜者 **原地替换** 旧条目，`result` 中始终只有一条，避免后续 C 标识符碰撞；
- **跨 `scan_lua_dir` 调用**（不同条目、不同 dir）：先到先得；
- 两种情况都会打印警告，包含保留与跳过的路径。

普通模式下 `scan_data_dir` 不做去重（因为普通模式下 `name` 天然唯一），依赖调用者自行约束。

---

## 5. `bytecode` 规则

- 默认 `false`：嵌入 **源码文本**，运行时用 `luaL_loadbuffer` 以文本模式加载；
- 设为 `true`：生成时用 `load(src)` + `string.dump(func)` 输出 **字节码**。

取舍：

| 选项 | 体积 | 隐藏源码 | Lua 版本耦合 |
|---|---|---|---|
| `bytecode = false` | 较大 | 否 | **无**，任何版本 luamake 都能构建，任何版本 Lua 都能加载 |
| `bytecode = true`  | 较小 | 是 | **宿主 Lua 版本 必须 == 目标 `luaversion`**，否则运行时加载失败 |

**默认源码嵌入** 是刻意的：luamake 宿主 Lua 版本可能与被嵌入目标的 `luaversion` 不一致，保留文本能避免字节码不兼容。

语法错误在代码生成阶段即刻失败（`syntax error in <path>`），不会等到运行期才暴露。

---

## 6. `bee_glue = true`：bee.lua 胶水层

启用后 [bee_glue.c](../../../scripts/lua_embed/bee_glue.c) 会被一并编译进来，并强制要求以下三个组存在（即使为空）：

```lua
data = {
    main    = { ... },   -- 必须存在
    preload = { ... },   -- 必须存在，自动切到 lua_mode
    data    = { ... },   -- 必须存在
}
```

缺少任一组会在 `write_config` 阶段 `assert` 失败，提示：

```
lua_embed: bee_glue requires group "main" to be defined (use an empty table {} if unused)
```

> 为什么强制存在？`bee_glue.c` 通过 `lua_embed.main` / `lua_embed.preload` / `lua_embed.data` 直接引用结构体字段；字段由组名派生，**任一组缺失都会造成 C 编译错误 `struct has no member`**。

启用后的运行时契约：

| 组 | 行为 |
|---|---|
| `main`    | 导出 `_bee_main(L)`：以 `main` 组的第一个条目（Lua 配置侧 `main[1]` / C 侧 `main[0]`）作为入口脚本，`luaL_loadbuffer` + `lua_pcall(0, 0, 0)` 执行 |
| `preload` | 导出 `_bee_preload_module(L)`：遍历全部条目，以 `name` 为键注入 `_PRELOAD`，每个 loader 是一个轻量闭包，`require` 触发时才 `luaL_loadbuffer` |
| `data`    | 注册 `require "bee.embed"`：返回一个带 `__index` 的 table，按字符串键线性查找 `lua_embed.data`，命中后缓存到 table 本体（后续 O(1)）。Lua 5.5 下用 `lua_pushexternalstring` 零拷贝，旧版本回退为 `lua_pushlstring` |

示例：

```lua
lm:lua_embed "myembed" {
    bee_glue = true,
    data = {
        main = {
            bytecode = true,
            "src/main.lua",                -- 入口脚本
        },
        preload = {
            bytecode = true,
            { dir = "lualib" },            -- 自动 lua_mode，require "foo" 即可
            { file = "scripts/init.lua", name = "init" },
        },
        data = {
            { file = "assets/config.json", name = "config.json" },
            { dir = "assets/res", prefix = "res/" },  -- 原始文件名扫描
        },
    },
}
```

在 Lua 侧：

```lua
local embed = require "bee.embed"
local cfg   = embed["config.json"]   -- string 或 nil；命中后缓存
```

---

## 7. 不使用 `bee_glue` 时如何接入

不启用 `bee_glue` 时：

- 组名 **完全自由**（合法 C 标识符即可），没有 `main` / `preload` / `data` 强制约束；
- 不注入任何 Lua 运行时钩子，拿到的就是一个纯数据 bundle，**由调用者决定用法**；
- 依然导出 `export_includes` / `export_objdeps`，C 侧照常 `#include "lua_embed_data.h"`。

三种常见接入姿势：

### 7.1 自定义 `package.searchers`

在 `searchers[2]` 插入一个查 `lua_embed.<group>` 的 C 函数：

```c
static int embed_searcher(lua_State* L) {
    const char* modname = luaL_checkstring(L, 1);
    for (const lua_embed_entry* e = lua_embed.preload; e->name; ++e) {
        if (strcmp(e->name, modname) == 0) {
            if (luaL_loadbuffer(L, e->data, e->size, modname) != LUA_OK)
                return lua_error(L);
            lua_pushstring(L, modname);
            return 2;
        }
    }
    lua_pushfstring(L, "\n\tno embedded module '%s'", modname);
    return 1;
}
```

> 注意：该组要用模块名作键，必须显式 `pattern = "?.lua;?/init.lua"`，否则键会是 `"foo.lua"` 而非 `"foo"`。

### 7.2 批量注入 `package.preload`

开局把整组塞进 `package.preload`，比自定义 searcher 更简单，等价于 `bee_glue` 对 `preload` 组的处理。

### 7.3 纯二进制资源

如果嵌入的不是 Lua 模块而是证书 / 配置 / schema，`lm:lua_embed` 也可以用——它退化为一个"内嵌资源表"，甚至可以给 **非 `lm:lua_exe`** 的普通 `lm:exe` 使用：

```lua
lm:lua_embed "resources" {
    data = {
        assets = {
            { file = "cert.pem",    name = "cert.pem" },
            { file = "schema.json", name = "schema.json" },
        },
    },
}

lm:exe "myapp" {
    deps    = "resources",
    sources = "src/main.c",   -- 按 lua_embed.assets 线性查找即可
}
```

---

## 8. C API（`lua_embed_data.h`）

```c
#include "lua_embed_data.h"

typedef struct lua_embed_entry {
    const char* name;   /* 条目名（文件名 / 模块名，取决于 §4） */
    const char* data;   /* 内容指针；末尾有 '\0' 哨兵（便于 lua_pushexternalstring） */
    size_t      size;   /* 字节数，不含哨兵 */
} lua_embed_entry;

/* 字段由组名派生，按字母序排列。以下仅示例： */
typedef struct lua_embed_bundle {
    const lua_embed_entry* data;     /* NULL-terminated */
    const lua_embed_entry* main;     /* NULL-terminated */
    const lua_embed_entry* preload;  /* NULL-terminated */
} lua_embed_bundle;

extern const lua_embed_bundle lua_embed;
```

遍历 / 查找惯用法：

```c
for (const lua_embed_entry* e = lua_embed.preload; e->name != NULL; ++e) { ... }

const lua_embed_entry* m = lua_embed.main;   /* 入口是第一个元素 */

for (const lua_embed_entry* e = lua_embed.data; e->name != NULL; ++e)
    if (strcmp(e->name, "config.json") == 0) { /* ... */ }
```

**查找复杂度**：线性扫描 O(N)。[bee_glue.c](../../../scripts/lua_embed/bee_glue.c) 中的 `bee.embed` 通过 **命中后缓存到 Lua table** 摊销为 O(1)；自定义实现若需要高频查找，建议采用相同模式，或在资产量非常大时拆分多个组 / 改用文件系统后端。

---

## 9. C 标识符碰撞

代码生成器对每个条目产生一个形如 `le_<group>_<name>` 的 C 标识符（见 `to_c_ident`）。由于 `name` 中非 `[A-Za-z0-9_]` 字符会被折叠成 `_`，不同 `name` 可能映射到同一基名（例如 `foo.bar` 与 `foo_bar`）。策略：

1. 同一次运行内，冲突时在基名后追加 **短 djb2 哈希**；
2. 映射通过双向表缓存，**在单次运行中保持纯函数性**；
3. 另外在循环里 `assert` 去重，任何破坏上述不变式的改动都会立刻暴露。

用户侧一般不会感知到这一点；当出现 `internal error: duplicate C identifier` 时，通常意味着组内存在 `name` 碰撞，应该改名或拆分。

---

## 10. 依赖方示例

```lua
lm:lua_embed "my_embed" {
    bee_glue = true,
    data = {
        main    = { bytecode = true, "src/main.lua" },
        preload = { bytecode = true, { dir = "lualib" } },
        data    = { { file = "assets/config.json", name = "config.json" } },
    },
}

-- ✅ 推荐：只写自己额外的 includes，headers & objdeps 由 lm:lua_embed 自动导出
lm:lua_src "my_glue" {
    deps     = "my_embed",
    includes = "3rd/bee.lua",
    sources  = "src/glue.cpp",
}

lm:lua_exe "my_app" {
    deps    = { "my_glue", "my_embed" },
    sources = "src/main.cpp",
}
```

❌ **不推荐**：硬编码内部路径或 phony 名：

```lua
lm:lua_src "my_glue" {
    includes = { "3rd/bee.lua", "_build/lua_embed/my_embed" },  -- 内部路径
    sources  = "src/glue.cpp",
    objdeps  = "__lua_embed_gen_my_embed__",                    -- 内部 phony 名
}
```

这两项都由 `lm:lua_embed` 通过 `deps` 自动传递。

---

## 11. 最小验证清单

写完 `lm:lua_embed` 后对照检查：

1. 组名是不是合法 C 标识符？
2. 启用 `bee_glue = true`？→ 必须定义 `main` / `preload` / `data` 三组（可以是空表 `{}`）。
3. 没启用 `bee_glue`？→ 如果该组要按模块名作键，**记得写 `pattern = "?.lua;?/init.lua"`**。
4. 依赖方只写 `deps = "xxx"`，不要重复指定 `includes` / `objdeps`。
5. 跨 Lua 版本分发？→ 不要开 `bytecode = true`。
6. 有跨组同名条目？→ 没关系，条目名只在组内唯一即可。
7. `[lua_embed] warning: ...` 出现时要读一下——通常是模板没匹配上或模块名碰撞。

---

## 参考实现

- [scripts/lua_embed.lua](../../../scripts/lua_embed.lua) — 配置写出、输入收集、`lua_mode` 判定
- [scripts/lua_embed/lua_embed_gen.lua](../../../scripts/lua_embed/lua_embed_gen.lua) — 实际扫描、字节码转换、C 代码生成
- [scripts/lua_embed/bee_glue.c](../../../scripts/lua_embed/bee_glue.c) — `bee_glue = true` 时的运行时胶水
- [scripts/writer.lua](../../../scripts/writer.lua) `api.lua_embed` — 目标注册与 `export_includes` / `export_objdeps` 导出
