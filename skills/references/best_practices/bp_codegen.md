# 最佳实践 - 代码生成与 objdeps

## 1. 代码生成管道

```lua
-- 步骤1: 生成配置头
lm:runlua "gen_config" {
    script = "gen_config.lua",
    inputs = "config.json",
    outputs = "$builddir/config.h",
}

-- 步骤2: 生成协议代码
lm:build "protocol_gen" {
    deps = "protoc",
    args = { "$bin/protoc", "--cpp_out=$builddir", "$in" },
    inputs = "protocol.proto",
    outputs = { "$builddir/protocol.pb.h", "$builddir/protocol.pb.cc" },
}

-- 步骤3: 依赖生成的文件
lm:exe "app" {
    deps = { "gen_config", "protocol_gen" },
    includes = "$builddir",
    sources = { "main.cpp", "$builddir/protocol.pb.cc" },
}
```

## 2. objdeps 用法

使用脚本动态生成的代码（如头文件、源文件），需要通过 `objdeps` 声明依赖，确保生成的文件在编译前已就绪。

`objdeps` 与 `deps` 的区别：
- `deps` 是**链接级别**依赖，确保依赖目标的产物参与链接。
- `objdeps` 是**编译级别**依赖，确保在编译源文件之前，指定的目标已经完成（例如已生成头文件）。

### 典型场景：依赖生成的头文件

```lua
-- 步骤1: 用脚本生成头文件
lm:runlua "gen_config" {
    script = "gen_config.lua",
    inputs = "config.json",
    outputs = "$builddir/config.h",
}

-- 步骤2: 源文件 #include 了生成的头文件，需要 objdeps 保证编译顺序
lm:exe "app" {
    includes = "$builddir",
    sources = "src/*.cpp",
    objdeps = "gen_config",  -- 编译前先完成 gen_config
}
```

### 典型场景：依赖自定义构建规则生成的代码

```lua
lm:build "gen_protocol" {
    deps = "protoc",
    args = { "$bin/protoc", "--cpp_out=$builddir", "$in" },
    inputs = "protocol.proto",
    outputs = { "$builddir/protocol.pb.h", "$builddir/protocol.pb.cc" },
}

lm:exe "server" {
    includes = "$builddir",
    sources = { "src/*.cpp", "$builddir/protocol.pb.cc" },
    objdeps = "gen_protocol",  -- 编译前先生成协议代码
}
```

> **注意**：如果源文件 `#include` 了动态生成的头文件，但没有声明 `objdeps`，可能导致编译时找不到头文件而失败。
