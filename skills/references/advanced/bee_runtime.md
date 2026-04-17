# Bee 运行时库

`luamake lua script.lua` 运行脚本时预加载 bee 库。

## API 参考来源

bee.lua 自身维护了一套完整的 API meta 信息（Lua EmmyLua 注解格式），位于 `bee.lua/meta/` 目录。**不要在 skill 中单独维护另一份 bee API 文档**，应直接读取 meta 文件获取最新的 API 定义和说明。

Meta 文件使用 `---@meta` 注解格式，包含类定义（`---@class`）、方法签名（`---描述` + `function`）、参数类型（`---@param`）、返回值类型（`---@return`）等信息。读取 meta 文件即可获得完整的 API 签名和中文说明。

## 模块列表

| 模块 | Meta 文件 | 说明 |
|------|-----------|------|
| `bee.filesystem` | `bee.lua/meta/filesystem.lua` | 文件系统操作、路径对象、目录遍历 |
| `bee.socket` | `bee.lua/meta/socket.lua` | TCP/UDP/Unix 套接字、端点 |
| `bee.subprocess` | `bee.lua/meta/subprocess.lua` | 子进程创建与管理 |
| `bee.thread` | `bee.lua/meta/thread.lua` | 多线程支持 |
| `bee.channel` | `bee.lua/meta/channel.lua` | 线程间通信管道 |
| `bee.async` | `bee.lua/meta/async.lua` | 异步 I/O（IOCP/io_uring/GCD） |
| `bee.epoll` | `bee.lua/meta/epoll.lua` | Epoll 风格 I/O 多路复用 |
| `bee.select` | `bee.lua/meta/select.lua` | Select 风格 I/O 多路复用 |
| `bee.sys` | `bee.lua/meta/sys.lua` | 系统工具（exe路径、文件锁等） |
| `bee.platform` | `bee.lua/meta/platform.lua` | 平台信息（OS、编译器、架构等） |
| `bee.serialization` | `bee.lua/meta/serialization.lua` | 序列化/反序列化（线程间数据传递） |
| `bee.time` | `bee.lua/meta/time.lua` | 时间操作（系统时间、单调时间、CPU时间） |
| `bee.filewatch` | `bee.lua/meta/filewatch.lua` | 文件系统监控 |
| `bee.crash` | `bee.lua/meta/crash.lua` | 崩溃处理（dump 生成） |
| `bee.debugging` | `bee.lua/meta/debugging.lua` | 调试支持（断点、调试器检测） |
| `bee.windows` | `bee.lua/meta/windows.lua` | Windows 平台特定功能 |

## 如何使用 Meta 文件

1. 当用户询问 bee 模块的 API 用法时，直接读取对应的 `bee.lua/meta/*.lua` 文件
2. Meta 文件中的 `---@class` 定义了对象类型，`---` 开头的注释行是方法说明，`---@param` / `---@return` 描述参数和返回值
3. Meta 文件是 bee.lua 项目的权威来源，始终以 meta 文件内容为准
