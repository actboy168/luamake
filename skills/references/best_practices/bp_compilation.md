# 最佳实践 - 条件编译与静态分析

## 1. 条件编译

```lua
lm:exe "app" {
    defines = {
        "MY_DEFINE",
        lm.os == "windows" and "PLATFORM_WINDOWS",
        lm.mode == "debug" and "DEBUG",
        lm.os ~= "windows" and "UNIX_LIKE",
    },
}

-- 更复杂的条件
defines = {
    lm.EXE ~= "lua" and "BEE_STATIC",  -- 静态构建时定义
}
```

## 2. 静态分析集成

```lua
lm:source_set "core" {
    sources = "core/*.cpp",
    
    msvc = lm.analyze and {
        flags = "/analyze",
    },
    gcc = lm.analyze and {
        flags = {
            "-fanalyzer",
            "-Wno-analyzer-use-of-uninitialized-value",
        },
    },
}
```
