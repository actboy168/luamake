# 最佳实践 - Lua 模块与测试

## 1. Lua C 模块

```lua
-- 静态嵌入到可执行文件
lm:lua_src "mymodule" {
    sources = "mymodule.c",
}

lm:lua_exe "app" {
    deps = "mymodule",
    sources = "main.cpp",
    main_script = "scripts/main.lua",  -- 入口脚本
}

-- 动态加载的模块
lm:lua_dll "mymodule" {
    sources = "mymodule.c",
    includes = "include",
}
```

## 2. 内置测试框架

```lua
if not lm.notest then
    local fs = require "bee.filesystem"
    local tests = {}
    
    -- 自动发现测试文件
    for file in fs.pairs_r(fs.path(lm.workdir) / "test") do
        if file:extension() == ".lua" then
            tests[#tests+1] = fs.relative(file, lm.workdir):string()
        end
    end
    table.sort(tests)

    -- 定义测试规则
    lm:rule "test" {
        args = { "$bin/app", "@test/runner.lua", "--touch", "$out" },
        description = "Run test.",
        pool = "console",
    }
    
    -- 测试目标
    lm:build "test" {
        rule = "test",
        deps = "app",
        inputs = tests,
        outputs = "$obj/test.stamp",
    }
end
```
