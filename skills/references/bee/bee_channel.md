# bee.channel

通道库，用于线程间通信。

## 用法

```lua
local channel = require "bee.channel"
```

---

## channel.create(name)

创建一个新的通道。

```lua
local ch = channel.create("my_channel")
```

---

## channel.destroy(name)

销毁一个通道。会清空通道中的所有数据。

```lua
channel.destroy("my_channel")
```

---

## channel.query(name)

查询一个已存在的通道。

```lua
local ch, err = channel.query("my_channel")
if not ch then
    print("Channel not found:", err)
end
```

---

## 通道对象 (bee.channel.box)

### channel_box:push(...)

向通道推送数据。数据会被序列化后发送，支持的数据类型与 bee.serialization 相同。

```lua
ch:push("hello", 123, { key = "value" })
```

### channel_box:pop()

从通道弹出数据。

```lua
local ok, msg1, msg2, msg3 = ch:pop()
if ok then
    print(msg1, msg2, msg3)
end
-- ok: 是否成功弹出数据，false 表示通道为空
```

### channel_box:fd()

获取通道的文件描述符。可用于 epoll/select 等待通道有数据。

```lua
local fd = ch:fd()
```

---

## 配合 epoll 使用

```lua
local channel = require "bee.channel"
local epoll = require "bee.epoll"

local ch = channel.create("my_channel")
local ep = epoll.create(10)

-- 添加通道到 epoll
ep:event_add(ch:fd(), epoll.EPOLLIN)

-- 等待事件
for data, events in ep:wait(-1) do
    if data == ch:fd() then
        local ok, ... = ch:pop()
        while ok do
            -- 处理数据
            print(...)
            ok, ... = ch:pop()
        end
    end
end
```

---

## 完整示例

```lua
-- 主线程
local thread = require "bee.thread"
local channel = require "bee.channel"

-- 创建通道
local ch = channel.create("main_channel")

-- 创建工作线程
local handle = thread.create([[
    local thread = require "bee.thread"
    local channel = require "bee.channel"
    
    local ch = channel.query("main_channel")
    if ch then
        -- 发送数据
        ch:push("worker_result", { status = "done", value = 42 })
    end
]])

-- 等待接收数据
while true do
    local ok, name, data = ch:pop()
    if ok then
        print("Received:", name, data.status, data.value)
        break
    end
    -- 可以在这里做其他事情
end

thread.wait(handle)
channel.destroy("main_channel")
```
