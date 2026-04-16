-- scripts/lua_embed.lua
-- Helper module for the lm:lua_embed target (registered in writer.lua).
-- Provides: config file generation and input file collection.

local fs     = require "bee.filesystem"
local fsutil = require "fsutil"
local pathutil = require "pathutil"

-- Directory containing lua_embed_gen.lua, lua_embed.h, etc.
local EMBED_DIR  = fsutil.join(package.procdir, "scripts", "lua_embed")
local GEN_SCRIPT = fsutil.join(EMBED_DIR, "lua_embed_gen.lua")
local HEADER     = fsutil.join(EMBED_DIR, "lua_embed.h")

local BEE_GLUE = fsutil.join(EMBED_DIR, "bee_glue.c")

local m = {}
m.GEN_SCRIPT = GEN_SCRIPT
m.HEADER     = HEADER
m.EMBED_DIR  = EMBED_DIR
m.BEE_GLUE   = BEE_GLUE

-- Recursively collect files under dirpath.
-- When lua_only=true, only *.lua files are collected.
function m.scan_inputs(dirpath, lua_only)
    local result = {}
    local root = fs.path(dirpath)
    if not fs.exists(root) then return result end
    local function recurse(base)
        for entry in fs.pairs(base) do
            if fs.is_directory(entry) then
                recurse(entry)
            else
                local name = entry:filename():string()
                if not lua_only or name:match("%.lua$") then
                    result[#result+1] = entry:string():gsub("\\", "/")
                end
            end
        end
    end
    recurse(root)
    table.sort(result)
    return result
end

-- 将 dir/file 路径相对于 rootdir 解析为绝对路径
local function resolve_path(rootdir, p)
    if rootdir then
        return pathutil.tostr(rootdir, p)
    end
    return p
end

-- Write a config.lua file for lua_embed_gen.lua to dofile().
-- attribute: the lm:lua_embed attribute table.
-- rootdir: (optional) root directory for resolving relative paths in attribute.
-- Returns the path of the written config file.
--
-- 只在内容实际变化时才写入文件，避免时间戳更新导致 Ninja 不必要的重建。
function m.write_config(outdir, attribute, rootdir)
    fs.create_directories(outdir)
    local config_path = outdir .. "/config.lua"

    local lines = {}
    lines[#lines+1] = "-- auto-generated lua_embed config"
    lines[#lines+1] = "return {"

    if attribute.bee_glue then
        -- bee_glue 文件路径写入配置，生成器会将其嵌入 lua_embed.c 中
        -- （通过 lua_embed_get_main() 访问，不暴露到 data_table）
        local main_path = resolve_path(rootdir, attribute.bee_glue)
        lines[#lines+1] = string.format("    main = %q,", main_path)
    end

    if attribute.bytecode then
        lines[#lines+1] = "    bytecode = true,"
    end

    -- preload
    lines[#lines+1] = "    preload = {"
    for _, e in ipairs(attribute.preload or {}) do
        if e.dir then
            local dir = resolve_path(rootdir, e.dir)
            local s = "        { dir = " .. string.format("%q", dir)
            if e.prefix and e.prefix ~= "" then
                s = s .. ", prefix = " .. string.format("%q", e.prefix)
            end
            if e.pattern then
                s = s .. ", pattern = " .. string.format("%q", e.pattern)
            end
            s = s .. " },"
            lines[#lines+1] = s
        elseif e.file then
            local file = resolve_path(rootdir, e.file)
            lines[#lines+1] = "        { file = " .. string.format("%q", file)
                .. ", name = " .. string.format("%q",
                    assert(e.name, "preload file entry requires 'name'"))
                .. " },"
        end
    end
    lines[#lines+1] = "    },"

    -- data
    lines[#lines+1] = "    data = {"
    for _, e in ipairs(attribute.data or {}) do
        if e.dir then
            local dir = resolve_path(rootdir, e.dir)
            local s = "        { dir = " .. string.format("%q", dir)
            if e.prefix then
                s = s .. ", prefix = " .. string.format("%q", e.prefix)
            end
            s = s .. " },"
            lines[#lines+1] = s
        elseif e.file then
            local file = resolve_path(rootdir, e.file)
            lines[#lines+1] = "        { file = " .. string.format("%q", file)
                .. ", name = " .. string.format("%q",
                    assert(e.name, "data file entry requires 'name'"))
                .. " },"
        end
    end
    lines[#lines+1] = "    },"

    lines[#lines+1] = "}"
    lines[#lines+1] = ""  -- 末尾换行

    local new_content = table.concat(lines, "\n")

    -- 只在内容变化时写入，避免时间戳更新导致不必要的重建
    local old_f = io.open(config_path, "rb")
    if old_f then
        local old_content = old_f:read "*a"
        old_f:close()
        if old_content == new_content then
            return config_path
        end
    end

    local f = assert(io.open(config_path, "wb"),
        "cannot write config: " .. config_path)
    f:write(new_content)
    f:close()
    return config_path
end

-- Collect all input files (for ninja dependency tracking).
-- 除了 Lua 源文件和生成器脚本外，config.lua 也作为输入被追踪，
-- 这样当用户修改 lua_embed 选项（bytecode/pattern/prefix/bee_glue 等）时，
-- Ninja 能检测到配置变化并重新生成 lua_embed.c。
-- write_config 已做内容比对，内容不变时不会更新文件时间戳，
-- 因此不会导致不必要的重建。
-- rootdir: (optional) root directory for resolving relative paths in attribute.
function m.collect_inputs(attribute, rootdir, config_path)
    local inputs = { GEN_SCRIPT }
    if config_path then
        inputs[#inputs+1] = config_path
    end
    for _, e in ipairs(attribute.preload or {}) do
        if e.dir then
            local dir = resolve_path(rootdir, e.dir)
            for _, p in ipairs(m.scan_inputs(dir, true)) do
                inputs[#inputs+1] = p
            end
        elseif e.file then
            inputs[#inputs+1] = resolve_path(rootdir, e.file)
        end
    end
    for _, e in ipairs(attribute.data or {}) do
        if e.dir then
            local dir = resolve_path(rootdir, e.dir)
            for _, p in ipairs(m.scan_inputs(dir, false)) do
                inputs[#inputs+1] = p
            end
        elseif e.file then
            inputs[#inputs+1] = resolve_path(rootdir, e.file)
        end
    end
    -- bee_glue 文件也需要追踪（会嵌入到 lua_embed.c 中）
    if attribute.bee_glue then
        inputs[#inputs+1] = resolve_path(rootdir, attribute.bee_glue)
    end
    table.sort(inputs)
    return inputs
end

return m
