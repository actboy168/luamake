# bee.socket

套接字库，支持 TCP/UDP 和 Unix 域套接字。

## 用法

```lua
local socket = require "bee.socket"
```

---

## 创建套接字

```lua
local sock = socket.create(protocol)
-- protocol: "tcp" | "udp" | "unix" | "tcp6" | "udp6"
```

---

## 套接字对象 (bee.socket.fd)

### 连接和绑定

```lua
-- 连接到指定地址
local ok, err = sock:connect("127.0.0.1", 8080)
-- 或使用端点对象
local ok, err = sock:connect(endpoint)

-- 绑定到指定地址
local ok, err = sock:bind("0.0.0.0", 8080)
-- 或
local ok, err = sock:bind(endpoint)

-- 开始监听
local ok, err = sock:listen(backlog)  -- backlog 默认为 5

-- 接受连接
local client, err = sock:accept()
-- 成功返回新套接字，等待中返回 false，失败返回 nil
```

### 数据传输

```lua
-- 接收数据 (TCP)
local data, err = sock:recv(len)  -- len 默认为缓冲区大小
-- 成功返回数据，等待中返回 false，连接关闭返回 nil

-- 发送数据 (TCP)
local sent, err = sock:send(data)
-- 成功返回发送的字节数，等待中返回 false，失败返回 nil

-- 从 UDP 套接字接收数据
local data, sender_or_err = sock:recvfrom(len)
-- 成功返回数据和发送方端点

-- 通过 UDP 套接字发送数据
local sent, err = sock:sendto(data, address, port)
-- 或
local sent, err = sock:sendto(data, endpoint)
```

### 状态和控制

```lua
-- 关闭套接字的读/写方向
sock:shutdown("r")  -- 关闭读方向
sock:shutdown("w")  -- 关闭写方向
sock:shutdown()     -- 关闭双向

-- 检查连接是否成功建立
local ok, err = sock:status()

-- 获取套接字信息
local endpoint, err = sock:info("peer")   -- 获取对端信息
local endpoint, err = sock:info("socket") -- 获取本端信息

-- 设置套接字选项
sock:option("reuseaddr", 1)
sock:option("sndbuf", 65536)
sock:option("rcvbuf", 65536)

-- 获取原始句柄
local handle = sock:handle()  -- 返回 lightuserdata

-- 分离套接字 (返回原始句柄并释放所有权)
local handle = sock:detach()

-- 关闭套接字
sock:close()
```

---

## 端点对象 (bee.endpoint)

```lua
-- 创建端点
local ep = socket.endpoint("unix", "/tmp/socket")
local ep = socket.endpoint("hostname", "example.com", 80)
local ep = socket.endpoint("inet", "127.0.0.1", 8080)
local ep = socket.endpoint("inet6", "::1", 8080)

-- 获取端点的值
local addr, port_or_type = ep:value()
-- 对于 inet/inet6：返回 IP地址, 端口号
-- 对于 unix：返回 路径, 类型
```

---

## 工具函数

### socket.pair()

创建一对已连接的套接字（用于进程间通信）：

```lua
local fd1, fd2_or_err = socket.pair()
```

### socket.fd()

从原始文件描述符创建套接字对象：

```lua
local sock = socket.fd(handle, no_ownership)
-- no_ownership: 如果为 true，不接管所有权（不会自动关闭）
```

### socket.gethostname()

获取主机名：

```lua
local hostname, err = socket.gethostname()
```
