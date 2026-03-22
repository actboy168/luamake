# bee.filesystem

文件系统操作库。

## 用法

```lua
local fs = require "bee.filesystem"
```

---

## 路径对象 (bee.fspath)

### 创建路径

```lua
local path = fs.path("/home/user") / "documents" / "file.txt"
```

### 路径操作

| 方法 | 返回值 | 描述 |
|------|--------|------|
| `path:string()` | string | 获取路径的字符串表示 |
| `path:filename()` | bee.fspath | 获取路径的文件名部分 |
| `path:parent_path()` | bee.fspath | 获取路径的父目录部分 |
| `path:stem()` | bee.fspath | 获取路径的主干部分(不含扩展名) |
| `path:extension()` | string | 获取路径的扩展名 |
| `path:is_absolute()` | boolean | 判断是否为绝对路径 |
| `path:is_relative()` | boolean | 判断是否为相对路径 |
| `path:remove_filename()` | bee.fspath | 移除路径中的文件名部分 |
| `path:replace_filename(replacement)` | bee.fspath | 替换路径中的文件名部分 |
| `path:replace_extension(replacement)` | bee.fspath | 替换路径中的扩展名部分 |
| `path:lexically_normal()` | bee.fspath | 返回词法上规范化的路径 |

### 操作符

```lua
local p1 = fs.path("/home")
local p2 = p1 / "user"           -- 路径拼接 (使用 / 分隔)
local p3 = p1 .. fs.path("user") -- 路径拼接 (直接拼接)
```

---

## 文件状态对象 (bee.file_status)

```lua
local status = fs.status("file.txt")

-- 获取文件类型
local type = status:type()
-- 返回: "none" | "not_found" | "regular" | "directory" | "symlink" | "block" | "character" | "fifo" | "socket" | "junction" | "unknown"

-- 判断方法
status:exists()           -- 是否存在
status:is_directory()     -- 是否为目录
status:is_regular_file()  -- 是否为普通文件
```

---

## 目录条目对象 (bee.directory_entry)

```lua
for path, entry in fs.pairs("directory") do
    print(entry:path())           -- 获取条目路径
    print(entry:type())           -- 获取文件类型
    print(entry:exists())         -- 是否存在
    print(entry:is_directory())   -- 是否为目录
    print(entry:is_regular_file()) -- 是否为普通文件
    print(entry:last_write_time()) -- 最后修改时间 (Unix时间戳，秒)
    print(entry:file_size())      -- 文件大小 (字节)
    entry:refresh()               -- 刷新缓存状态
    entry:status()                -- 获取文件状态
    entry:symlink_status()        -- 获取符号链接状态(不跟踪)
end
```

---

## 文件状态查询

```lua
fs.status(p)            -- 获取文件状态
fs.symlink_status(p)    -- 获取符号链接状态(不跟踪符号链接)
fs.exists(p)            -- 判断文件或目录是否存在
fs.is_directory(p)      -- 判断是否为目录
fs.is_regular_file(p)   -- 判断是否为普通文件
fs.file_size(p)         -- 获取文件大小 (字节)
```

---

## 目录操作

```lua
fs.create_directory(p)       -- 创建单个目录，返回是否创建成功
fs.create_directories(p)     -- 递归创建目录，返回是否创建成功
fs.remove(p)                 -- 删除文件或空目录，返回是否删除成功
fs.remove_all(p)             -- 递归删除，返回删除的文件/目录数量
fs.rename(from, to)          -- 重命名或移动文件/目录
fs.copy(from, to, options)   -- 复制文件或目录
fs.copy_file(from, to, options) -- 复制单个文件，返回是否成功
```

---

## 目录遍历

```lua
-- 非递归遍历
for path, entry in fs.pairs("directory", options) do
    print(path:string(), entry:is_directory())
end

-- 递归遍历
for path, entry in fs.pairs_r("directory", options) do
    print(path:string())
end
```

---

## 路径操作

```lua
fs.absolute(p)        -- 获取绝对路径
fs.canonical(p)       -- 获取规范路径(解析符号链接和..等)
fs.relative(p, base)  -- 获取相对路径，base默认为当前工作目录
fs.current_path()     -- 获取当前工作目录
fs.current_path(p)    -- 设置当前工作目录
fs.temp_directory_path() -- 获取临时目录路径
```

---

## 文件时间和权限

```lua
-- 最后修改时间 (Unix时间戳，秒)
fs.last_write_time(p)       -- 获取
fs.last_write_time(p, time) -- 设置

-- 文件权限
fs.permissions(p)                    -- 获取权限
fs.permissions(p, perms, options)    -- 设置权限
```

---

## 符号链接和硬链接

```lua
fs.create_symlink(target, link)         -- 创建符号链接(文件)
fs.create_directory_symlink(target, link) -- 创建符号链接(目录)
fs.create_hard_link(target, link)       -- 创建硬链接
```

---

## 文件系统空间信息

```lua
local space = fs.space("C:")
print(space.capacity)   -- 总容量 (字节)
print(space.free)       -- 空闲空间 (字节)
print(space.available)  -- 可用空间 (字节)
```

---

## 常量和选项

### 复制选项 (fs.copy_options)

```lua
fs.copy_options.none              -- 无特殊选项
fs.copy_options.skip_existing     -- 跳过已存在的文件
fs.copy_options.overwrite_existing -- 覆盖已存在的文件
fs.copy_options.update_existing   -- 仅当源文件较新时覆盖
fs.copy_options.recursive         -- 递归复制目录
fs.copy_options.copy_symlinks     -- 复制符号链接而非其目标
fs.copy_options.skip_symlinks     -- 跳过符号链接
fs.copy_options.directories_only  -- 仅复制目录结构
fs.copy_options.create_symlinks   -- 创建符号链接而非复制
fs.copy_options.create_hard_links -- 创建硬链接而非复制
```

### 权限选项 (fs.perm_options)

```lua
fs.perm_options.replace   -- 替换权限
fs.perm_options.add       -- 添加权限
fs.perm_options.remove    -- 移除权限
fs.perm_options.nofollow  -- 不跟踪符号链接
```

### 目录遍历选项 (fs.directory_options)

```lua
fs.directory_options.none                    -- 无特殊选项
fs.directory_options.follow_directory_symlink -- 跟踪目录符号链接
fs.directory_options.skip_permission_denied  -- 跳过权限拒绝的条目
```
