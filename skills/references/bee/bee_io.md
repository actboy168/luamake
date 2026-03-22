# bee I/O 模块

## bee.serialization

序列化库，用于在线程间传递复杂数据结构。

### 支持的类型

- 支持：nil, boolean, number, string, table, light C function
- 不支持：function (非 light C function), thread, userdata

### serialization.pack(...)

将数据序列化并返回轻量用户数据指针。

```lua
local data = serialization.pack("hello", 123, { a = 1 })
-- 注意：必须调用 unpack 释放内存
local s1, s2, s3 = serialization.unpack(data)
```

### serialization.packstring(...)

将数据序列化为字符串。

```lua
local str = serialization.packstring("data", 456)
local d1, d2 = serialization.unpack(str)
```

### serialization.unpack(data)

反序列化数据。

```lua
-- 支持 lightuserdata, string, userdata, function
local ... = serialization.unpack(data)
```

### serialization.lightuserdata(ud)

将 userdata 转换为 lightuserdata。

```lua
local ld = serialization.lightuserdata(ud)
```

---

## bee.time

时间库。

### time.time()

获取当前系统时间，返回自 Unix 纪元以来的毫秒数。

```lua
print(time.time())  -- Unix 时间戳，毫秒
```

### time.monotonic()

获取单调递增时间，用于测量时间间隔，不受系统时间调整影响。

```lua
local start = time.monotonic()
-- ... 做一些工作 ...
local elapsed = time.monotonic() - start  -- 毫秒
```

### time.thread()

获取当前线程的 CPU 时间。

```lua
print(time.thread())  -- CPU 时间，毫秒
```

---

## bee.filewatch

文件监控库。

### filewatch.create()

创建文件监控器。

```lua
local filewatch = require "bee.filewatch"
local watch = filewatch.create()
```

### 监控器方法

```lua
-- 添加监控路径（会自动转换为绝对路径）
watch:add("/path/to/watch")

-- 设置是否递归监控子目录
watch:set_recursive(true)

-- 设置是否跟踪符号链接
watch:set_follow_symlinks(true)

-- 设置过滤器函数
watch:set_filter(function(path)
    return path:match("%.lua$") ~= nil  -- 只监控 .lua 文件
end)
watch:set_filter(nil)  -- 清除过滤器

-- 检查并获取文件变更事件
local type, path = watch:select()
-- type: "modify"（修改）或 "rename"（重命名），无事件返回 nil
```

### 示例

```lua
local filewatch = require "bee.filewatch"

local watch = filewatch.create()
watch:add("/project/src")
watch:set_recursive(true)
watch:set_filter(function(path)
    return path:match("%.lua$") ~= nil
end)

while true do
    local type, path = watch:select()
    if type then
        print(type, path)
    end
end
```

---

## bee.epoll

Epoll I/O 多路复用库。跨平台的 epoll 风格 API，在 Windows 上使用 IOCP 实现。

### 事件标志

```lua
epoll.EPOLLIN      -- 可读事件
epoll.EPOLLPRI     -- 紧急数据可读
epoll.EPOLLOUT     -- 可写事件
epoll.EPOLLERR     -- 错误事件
epoll.EPOLLHUP     -- 挂起事件
epoll.EPOLLRDNORM  -- 普通数据可读
epoll.EPOLLRDBAND  -- 优先数据可读
epoll.EPOLLWRNORM  -- 普通数据可写
epoll.EPOLLWRBAND  -- 优先数据可写
epoll.EPOLLMSG     -- 消息事件
epoll.EPOLLRDHUP   -- 对端关闭连接
epoll.EPOLLONESHOT -- 一次性事件（触发后自动删除）
```

### epoll.create(max_events)

创建 Epoll 实例。

```lua
local ep = epoll.create(10)  -- 最大事件数量
```

### Epoll 实例方法

```lua
-- 添加事件监听
ep:event_add(fd, events, userdata)
-- fd: 套接字或文件描述符
-- events: 事件标志，可组合多个 EPOLL* 常量
-- userdata: 关联的用户数据，默认为 fd 本身

-- 修改事件监听
ep:event_mod(fd, events, userdata)

-- 删除事件监听
ep:event_del(fd)

-- 等待事件
for data, events in ep:wait(timeout) do
    -- data: 关联的用户数据
    -- events: 事件标志
    -- timeout: -1 表示无限等待
end

-- 关闭
ep:close()
```

### 示例：TCP 服务器

```lua
local epoll = require "bee.epoll"
local socket = require "bee.socket"

local ep = epoll.create(10)
local server = socket.create("tcp")
server:bind("0.0.0.0", 8080)
server:listen()

ep:event_add(server, epoll.EPOLLIN)

while true do
    for data, events in ep:wait(-1) do
        if data == server then
            local client = server:accept()
            if client then
                ep:event_add(client, epoll.EPOLLIN)
            end
        else
            local data, err = data:recv(1024)
            if data then
                -- 处理数据
            else
                ep:event_del(data)
                data:close()
            end
        end
    end
end
```

---

## bee.select

Select I/O 多路复用库。

### 事件标志

```lua
select.SELECT_READ   -- 读事件标志
select.SELECT_WRITE  -- 写事件标志
```

### select.create()

创建 Select 上下文。

```lua
local ctx = select.create()
```

### Select 上下文方法

```lua
-- 添加事件监听
ctx:event_add(fd, events, userdata)

-- 修改事件监听
ctx:event_mod(fd, events)

-- 删除事件监听
ctx:event_del(fd)

-- 等待事件
for data, events in ctx:wait(timeout) do
    -- timeout: -1 表示无限等待
end

-- 关闭
ctx:close()
```

### 示例

```lua
local select = require "bee.select"

local ctx = select.create()
ctx:event_add(socket1, select.SELECT_READ)
ctx:event_add(socket2, select.SELECT_READ | select.SELECT_WRITE)

for data, events in ctx:wait(1000) do
    if events & select.SELECT_READ then
        -- 数据可读
    end
    if events & select.SELECT_WRITE then
        -- 可写
    end
end

ctx:close()
```
