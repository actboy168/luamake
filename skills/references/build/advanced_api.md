# 高级 API

## 自定义构建规则

```lua
-- 定义规则
lm:rule "gen" {
    args = { "$bin/generator", "-o", "$out", "$in" },
    description = "Generating $out...",
    pool = "console",  -- 可见输出
}

-- 使用规则
lm:build "generated.h" {
    rule = "gen",
    inputs = "template.h.in",
    outputs = "$builddir/gen/generated.h",
}

-- 或直接指定命令
lm:build "output.txt" {
    deps = "tool",
    args = { "$bin/tool", "$in", "$out" },
    inputs = "input.txt",
    outputs = "$bin/output.txt",
}
```

## 运行 Lua 脚本

```lua
lm:runlua "gen_config" {
    script = "configure.lua",
    args = { "$in", "$out" },
    inputs = "config.h.in",
    outputs = "$builddir/config.h",
}
```

## 文件操作

```lua
-- 复制文件
lm:copy "copy_lua" {
    inputs = "src/main.lua",
    outputs = "$bin/main.lua",
    deps = "app",  -- 可选依赖
}

-- MSVC DLL 复制
lm:msvc_copydll "copy_asan" {
    type = "asan",  -- "vcrt" 或 "asan"
    outputs = "$bin",
}
```

## 检查与版本

```lua
-- 检查目标是否存在
if lm:has("module") then
    deps[#deps+1] = "module"
end

-- 版本要求
lm:required_version "1.6"

-- 输出 compile_commands.json
lm.compile_commands = "$builddir"
```
