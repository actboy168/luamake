# 平台/编译器特定配置

目标属性支持按平台或编译器进行条件覆盖。只需在目标属性中嵌套一个与平台或编译器同名的子表，构建时 luamake 会自动选择匹配当前环境的配置并合并到主属性中。

## 平台特定配置

支持的平台名与 `lm.os` 的取值一致：

| 平台键 | 说明 |
|--------|------|
| `windows` | Windows |
| `linux` | Linux |
| `macos` | macOS |
| `ios` | iOS |
| `android` | Android |
| `freebsd` | FreeBSD |
| `openbsd` | OpenBSD |
| `netbsd` | NetBSD |

```lua
lm:exe "myapp" {
    sources = "src/*.cpp",
    windows = {
        sources = "src/win/*.cpp",
        links = { "ws2_32", "user32" },
        defines = "WIN32_LEAN_AND_MEAN",
    },
    linux = {
        sources = "src/linux/*.cpp",
        links = { "pthread", "dl" },
    },
    macos = {
        sources = "src/mac/*.mm",
        frameworks = { "Foundation", "Cocoa" },
    },
}
```

## 编译器特定配置

支持的编译器名与 `lm.compiler` 的取值一致：

| 编译器键 | 说明 |
|----------|------|
| `msvc` | Microsoft Visual C++ |
| `gcc` | GCC |
| `clang` | Clang |
| `clang_cl` | Clang-CL（Windows 上的 Clang MSVC 兼容模式） |
| `mingw` | MinGW（Windows 上的 GCC，`lm.os == "windows"` 且 shell 为 `sh` 时生效） |
| `emcc` | Emscripten |

```lua
lm:exe "myapp" {
    sources = "src/*.cpp",
    msvc = {
        flags = "/utf-8",
        ldflags = "/SUBSYSTEM:CONSOLE",
    },
    gcc = {
        flags = { "-Wno-unused-parameter" },
        links = "stdc++fs",
    },
    clang = {
        flags = { "-Wno-unused-parameter" },
    },
}
```

## 合并规则

平台和编译器配置可以同时使用，luamake 会按以下顺序合并：

1. 主属性（公共部分）
2. 匹配的平台子表（如 `windows`）
3. 匹配的编译器子表（如 `msvc`）
4. 特殊情况：`mingw` 在 `lm.os == "windows"` 且 shell 为 `sh` 时生效
5. 特殊情况：`clang_cl` 在 `lm.compiler == "msvc"` 且 `cc` 为 `clang-cl` 时生效

列表类属性（`sources`、`defines`、`links` 等）会**追加**到主属性中，标量属性会**覆盖**主属性。

## 编译选项属性

以下属性用于控制编译行为，可在目标或 `lm:conf` 中设置：

| 属性 | 类型 | 可选值 | 默认值 | 说明 |
|------|------|--------|--------|------|
| `c` | string | `"c89"` `"c99"` `"c11"` `"c17"` `"c23"` `"clatest"` | `""` (编译器默认) | C 标准 |
| `cxx` | string | `"c++11"` `"c++14"` `"c++17"` `"c++20"` `"c++23"` `"c++latest"` | `""` (编译器默认) | C++ 标准 |
| `warnings` | string | `"off"` `"on"` `"all"` `"error"` `"strict"` | `"on"` | 警告级别 |
| `optimize` | string | `"off"` `"size"` `"speed"` `"maxspeed"` | debug 模式下 `"off"`，否则 `"speed"` | 优化级别 |
| `mode` | string | `"debug"` `"release"` | `"release"` | 构建模式 |
| `crt` | string | `"dynamic"` `"static"` | `"dynamic"` | C 运行时链接方式 |
| `visibility` | string | `"hidden"` `"default"` | `"hidden"` | 符号可见性（非 Windows） |
| `rtti` | string | `"on"` `"off"` | `"on"` | C++ RTTI |
| `lto` | string | `"on"` `"off"` `"thin"` (仅 Clang) | MSVC release 模式下 `"on"`，否则 `"off"` | 链接时优化 |
| `permissive` | string | `"on"` `"off"` | `"off"` | MSVC 宽容模式（仅 MSVC） |

## 交叉编译（Clang）

Clang 支持通过 `target`、`arch`、`vendor`、`sys` 属性控制交叉编译目标：

```lua
-- 方式一：直接指定 target triple
lm:conf {
    target = "aarch64-linux-gnu",
}

-- 方式二：分别指定各部分
lm:conf {
    arch = "aarch64",
    vendor = "linux",
    sys = "gnu",
}

-- macOS 最低版本
lm:conf {
    sys = "macos14.0",   -- 等效于 -mmacosx-version-min=14.0
}

-- iOS 最低版本
lm:conf {
    sys = "ios17.0",     -- 等效于 -miphoneos-version-min=17.0
}

-- 仅指定架构（macOS/iOS 通用二进制）
lm:conf {
    arch = "arm64",
}
```

## MSVC 特有功能

### msvc_copydll

复制 MSVC 运行时 DLL 到指定目录：

```lua
lm:msvc_copydll "copy_vcrt" {
    type = "vcrt",        -- "vcrt" | "ucrt" | "asan"
    outputs = "$bin",
}
```

| type | 说明 |
|------|------|
| `vcrt` | Visual C++ 运行时 DLL |
| `ucrt` | 通用 C 运行时 DLL |
| `asan` | AddressSanitizer DLL |
