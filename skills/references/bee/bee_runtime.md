# Bee 运行时库

`luamake lua script.lua` 运行脚本时预加载 bee 库。各模块的详细 API 文档见 `skills/references/bee/bee_*.md`。

## 文件系统示例

```lua
local fs = require "bee.filesystem"

-- 遍历目录
for path, entry in fs.pairs(".") do
    print(path:string(), entry:is_directory())
end

-- 递归遍历
for file in fs.pairs_r("src") do
    if file:extension() == ".lua" then
        print(file)
    end
end

-- 路径操作
local path = fs.path("/usr/local/bin")
print(path:filename())      -- bin
print(path:extension())     -- "" (无扩展名)
print(path:parent_path())   -- /usr/local

-- 创建目录
fs.create_directories("build/output")

-- 复制文件
fs.copy_file("source.txt", "dest.txt")

-- 检查存在
if fs.exists("config.json") then
    -- ...
end
```

## 子进程示例

```lua
local subprocess = require "bee.subprocess"

-- 运行命令并获取输出
local proc = subprocess.spawn { 
    "ls", "-la", 
    stdout = true 
}
for line in proc.stdout:lines() do
    print(line)
end
proc:wait()

-- 运行命令并等待完成
local proc = subprocess.spawn { 
    "git", "status",
    stdout = "pipe",
    stderr = "pipe",
}
local exit_code = proc:wait()
print("Exit code:", exit_code)

-- 环境变量
local proc = subprocess.spawn {
    "echo", "hello",
    env = { MY_VAR = "value" },
    stdout = true,
}
```

## 套接字示例

```lua
local socket = require "bee.socket"

-- TCP 客户端
local client = socket.tcp()
client:connect("127.0.0.1", 8080)
client:send("GET / HTTP/1.0\r\n\r\n")
local response = client:recv(4096)
print(response)
client:close()

-- TCP 服务器
local server = socket.tcp()
server:bind("0.0.0.0", 8080)
server:listen()
local client = server:accept()
-- ...
```
