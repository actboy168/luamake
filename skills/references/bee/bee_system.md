# bee 系统模块

## bee.sys

系统工具库。

### sys.exe_path()

获取当前可执行文件的路径。

```lua
local path, err = sys.exe_path()
print(path:string())
```

### sys.dll_path()

获取当前动态库的路径。

```lua
local path, err = sys.dll_path()
```

### sys.filelock(path)

创建文件锁。如果文件已被锁定，返回 nil。锁会在文件句柄关闭时自动释放。

```lua
local lock, err = sys.filelock("/tmp/myapp.lock")
if not lock then
    print("Another instance is running:", err)
    os.exit(1)
end
-- 程序结束时锁会自动释放
```

### sys.fullpath(path)

获取文件的完整路径，会解析符号链接等。

```lua
local path, err = sys.fullpath("relative/path")
```

---

## bee.platform

平台信息模块（模块返回的是表而不是类）。

### 字段

```lua
local platform = require "bee.platform"

-- 操作系统名称
print(platform.os)
-- "windows" | "android" | "linux" | "netbsd" | "freebsd" | "openbsd" | "ios" | "macos" | "unknown"

-- 编译器类型
print(platform.Compiler)
-- "clang" | "msvc" | "gcc" | "unknown"

-- 编译器版本字符串
print(platform.CompilerVersion)

-- C 运行时库类型
print(platform.CRT)
-- "bionic" | "msvc" | "libstdc++" | "libc++" | "unknown"

-- C 运行时库版本字符串
print(platform.CRTVersion)

-- 架构
print(platform.Arch)
-- "arm64" | "x86" | "x86_64" | "arm" | "riscv" | "wasm32" | "wasm64" | "mips64el" | "loongarch64" | "ppc64" | "ppc" | "unknown"

-- 是否为调试构建
print(platform.DEBUG)

-- 操作系统版本信息
print(platform.os_version.major)    -- 主版本号
print(platform.os_version.minor)    -- 次版本号
print(platform.os_version.revision) -- 修订版本号
```

---

## bee.crash

崩溃处理库。

### crash.create_handler(dump_path)

创建崩溃处理器。当程序崩溃时，会在指定路径生成 dump 文件。

```lua
local crash = require "bee.crash"
local handler = crash.create_handler("./crash_dumps")
```

---

## bee.debugging

调试库。

### debugging.breakpoint()

触发断点。在调试器中会中断执行。

```lua
local dbg = require "bee.debugging"
dbg.breakpoint()  -- 总是断点
```

### debugging.is_debugger_present()

检查是否有调试器附加。

```lua
if dbg.is_debugger_present() then
    print("Debugger attached!")
end
```

### debugging.breakpoint_if_debugging()

仅在有调试器附加时触发断点。

```lua
dbg.breakpoint_if_debugging()  -- 有调试器才断点
```

---

## bee.windows

Windows 平台特定功能库。

### windows.u2a(str)

将 UTF-8 字符串转换为 ANSI (GBK) 编码。

```lua
local ansi = windows.u2a("UTF-8 字符串")
```

### windows.a2u(str)

将 ANSI (GBK) 字符串转换为 UTF-8 编码。

```lua
local utf8 = windows.a2u("ANSI 字符串")
```

### windows.filemode(file, mode)

设置文件的文本/二进制模式。

```lua
windows.filemode(io.stdout, "b")  -- 二进制模式
windows.filemode(io.stdout, "t")  -- 文本模式
```

### windows.isatty(file)

判断文件句柄是否为 TTY (终端)。

```lua
if windows.isatty(io.stdout) then
    print("Output is terminal")
end
```

### windows.write_console(file, msg)

向 Windows 控制台写入内容。使用 WriteConsoleW API，能正确处理 UTF-16 编码。

```lua
windows.write_console(io.stdout, "Hello 世界!")
```

### windows.is_ssd(drive)

检测磁盘驱动器是否为 SSD。

```lua
if windows.is_ssd("C:") then
    print("C: is an SSD")
end
```
