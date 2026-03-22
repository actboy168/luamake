# bee.subprocess

子进程库，用于创建和管理子进程。

## 用法

```lua
local subprocess = require "bee.subprocess"
```

---

## subprocess.spawn(args)

启动子进程。

### 参数 (bee.subprocess.spawn_args)

| 字段 | 类型 | 描述 |
|------|------|------|
| `[1]` | string\|bee.fspath | 程序路径（必需） |
| `[2..n]` | string\|bee.fspath\|table | 命令行参数（可嵌套数组） |
| `cwd` | string\|bee.fspath | 工作目录 |
| `stdin` | boolean\|file* | true 则创建管道，也可传入文件句柄 |
| `stdout` | boolean\|file* | true 则创建管道，也可传入文件句柄 |
| `stderr` | boolean\|file*\|"stdout" | true 则创建管道，"stdout" 则共享 stdout |
| `env` | table | 环境变量表，false 表示删除该变量 |
| `suspended` | boolean | 是否以挂起状态启动 |
| `detached` | boolean | 是否以分离模式启动 |
| `console` | string | Windows 控制台模式: "new"\|"disable"\|"inherit"\|"detached" |
| `hideWindow` | boolean | Windows 是否隐藏窗口 |
| `searchPath` | boolean | Windows 是否搜索 PATH |

### 示例

```lua
-- 简单启动
local proc = subprocess.spawn { "ls", "-la" }
proc:wait()

-- 捕获输出
local proc = subprocess.spawn {
    "ls", "-la",
    stdout = true,
}
for line in proc.stdout:lines() do
    print(line)
end
local exit_code = proc:wait()

-- 重定向输入输出
local proc = subprocess.spawn {
    "grep", "pattern",
    stdin = true,
    stdout = true,
}
proc.stdin:write("some text\n")
proc.stdin:close()
local result = proc.stdout:read("*a")
proc:wait()

-- 工作目录和环境变量
local proc = subprocess.spawn {
    "ls",
    cwd = "/home/user",
    env = {
        PATH = "/usr/bin",
        HOME = "/home/user",
        UNSET_VAR = false,  -- 删除变量
    }
}

-- 分离进程（fire and forget）
local proc = subprocess.spawn {
    "long_running_task",
    detached = true,
}
proc:detach()

-- 挂起启动
local proc = subprocess.spawn {
    "task",
    suspended = true,
}
-- ... 做一些事情 ...
proc:resume()  -- 恢复执行
proc:wait()

-- 嵌套参数
local proc = subprocess.spawn {
    "cmd",
    { "/c", "echo", "hello" },  -- 嵌套数组会被展开
}
```

---

## 进程对象 (bee.subprocess.process)

### 字段

```lua
proc.stdin   -- 标准输入文件句柄（如果请求了的话）
proc.stdout  -- 标准输出文件句柄（如果请求了的话）
proc.stderr  -- 标准错误文件句柄（如果请求了的话）
```

### 方法

```lua
-- 等待进程结束
local exit_code, err = proc:wait()

-- 向进程发送信号
proc:kill()      -- 发送 SIGTERM (15)
proc:kill(9)     -- 发送 SIGKILL

-- 获取进程 ID
local pid = proc:get_id()

-- 检查进程是否正在运行
local running = proc:is_running()

-- 恢复挂起的进程
local ok = proc:resume()

-- 获取进程的原生句柄
local handle = proc:native_handle()

-- 分离进程（分离后进程不再由当前对象管理）
local ok = proc:detach()
```

---

## 工具函数

### subprocess.select(processes, timeout)

等待多个进程中的任意一个结束：

```lua
local procs = { proc1, proc2, proc3 }
local ok, err = subprocess.select(procs, 1000)  -- 超时 1 秒
-- timeout: -1 表示无限等待
```

### subprocess.peek(file)

检查管道中是否有可读数据：

```lua
local bytes, err = subprocess.peek(proc.stdout)
```

### subprocess.setenv(name, value)

设置环境变量：

```lua
local ok, err = subprocess.setenv("MY_VAR", "value")
```

### subprocess.get_id()

获取当前进程 ID：

```lua
local pid = subprocess.get_id()
```

### subprocess.quotearg(arg)

对参数进行命令行引用处理（处理空格、引号等特殊字符）：

```lua
local quoted = subprocess.quotearg("arg with spaces")
```
