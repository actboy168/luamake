# bee.thread

线程库，支持多线程和隔离的 Lua 状态机。

## 用法

```lua
local thread = require "bee.thread"
```

---

## 全局字段

```lua
thread.id  -- 当前线程的 ID（主线程为 0）
```

---

## thread.create(source, ...)

创建一个新的线程。线程中可以访问 bee.* 模块，但不共享全局变量。

```lua
-- 创建线程
local handle = thread.create([[
    local thread = require "bee.thread"
    print("Thread ID:", thread.id)
    thread.sleep(1000)  -- 休眠 1 秒
    print("Thread done!")
]], arg1, arg2)  -- 传递给线程的参数，会被序列化
```

---

## thread.sleep(msec)

使当前线程休眠。

```lua
thread.sleep(1000)  -- 休眠 1000 毫秒
```

---

## thread.wait(handle)

等待线程结束。

```lua
thread.wait(handle)
```

---

## thread.setname(name)

设置当前线程的名称（主要用于调试）。

```lua
thread.setname("worker")
```

---

## thread.errlog()

获取线程错误日志。如果有线程发生错误，返回错误消息。

```lua
local err = thread.errlog()
if err then
    print("Thread error:", err)
end
```

---

## thread.preload_module(L)

预加载模块。在新线程中调用以注册所有 bee.* 模块。

```lua
-- 通常不需要手动调用
thread.preload_module(L)
```

---

## 完整示例

```lua
local thread = require "bee.thread"
local channel = require "bee.channel"

-- 创建通道用于线程通信
local ch = channel.create("worker_channel")

-- 创建工作线程
local handle = thread.create([[
    local thread = require "bee.thread"
    local channel = require "bee.channel"
    
    thread.setname("worker")
    print("Worker thread started, ID:", thread.id)
    
    local ch = channel.query("worker_channel")
    if ch then
        ch:push("hello from worker")
    end
    
    thread.sleep(500)
    print("Worker done!")
]])

-- 主线程接收数据
local ok, msg = ch:pop()
if ok then
    print("Received:", msg)
end

-- 等待线程结束
thread.wait(handle)

-- 检查错误
local err = thread.errlog()
if err then
    print("Thread error:", err)
end
```
