-- scripts/lua_embed.lua
-- Helper module for the lm:lua_embed target (registered in writer.lua).
-- Provides: config file generation and input file collection.

local fs     = require "bee.filesystem"
local fsutil = require "fsutil"

-- Directory containing lua_embed_gen.lua, lua_embed.h, etc.
local EMBED_DIR  = fsutil.join(package.procdir, "compile", "lua_embed")
local GEN_SCRIPT = fsutil.join(EMBED_DIR, "lua_embed_gen.lua")
local HEADER     = fsutil.join(EMBED_DIR, "lua_embed.h")

local m = {}
m.GEN_SCRIPT = GEN_SCRIPT
m.HEADER     = HEADER
m.EMBED_DIR  = EMBED_DIR

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
    return result
end

-- Write a config.lua file for lua_embed_gen.lua to dofile().
-- attribute: the lm:lua_embed attribute table.
-- Returns the path of the written config file.
function m.write_config(outdir, attribute)
    fs.create_directories(outdir)
    local config_path = outdir .. "/config.lua"
    local f = assert(io.open(config_path, "wb"),
        "cannot write config: " .. config_path)

    f:write("-- auto-generated lua_embed config\n")
    f:write("return {\n")

    if attribute.glue == "bee" then
        f:write(string.format("    main = %q,\n",
            assert(attribute.main, "lua_embed glue='bee' requires 'main'")))
        if attribute.no_main then
            f:write("    no_main = true,\n")
        end
    end

    -- preload
    f:write("    preload = {\n")
    for _, e in ipairs(attribute.preload or {}) do
        if e.dir then
            f:write("        { dir = " .. string.format("%q", e.dir))
            if e.prefix and e.prefix ~= "" then
                f:write(", prefix = " .. string.format("%q", e.prefix))
            end
            if e.pattern then
                f:write(", pattern = " .. string.format("%q", e.pattern))
            end
            f:write(" },\n")
        elseif e.file then
            f:write("        { file = " .. string.format("%q", e.file)
                .. ", name = " .. string.format("%q",
                    assert(e.name, "preload file entry requires 'name'"))
                .. " },\n")
        end
    end
    f:write("    },\n")

    -- data
    f:write("    data = {\n")
    for _, e in ipairs(attribute.data or {}) do
        if e.dir then
            f:write("        { dir = " .. string.format("%q", e.dir))
            if e.prefix then
                f:write(", prefix = " .. string.format("%q", e.prefix))
            end
            f:write(" },\n")
        elseif e.file then
            f:write("        { file = " .. string.format("%q", e.file)
                .. ", name = " .. string.format("%q",
                    assert(e.name, "data file entry requires 'name'"))
                .. " },\n")
        end
    end
    f:write("    },\n")

    f:write("}\n")
    f:close()
    return config_path
end

-- Collect all input files (for ninja dependency tracking).
-- config.lua is a configure-time artifact; only Lua source files and the
-- generator script itself are listed as inputs so ninja only reruns when
-- the actual source content changes.
function m.collect_inputs(attribute)
    local inputs = { GEN_SCRIPT }
    for _, e in ipairs(attribute.preload or {}) do
        if e.dir then
            for _, p in ipairs(m.scan_inputs(e.dir, true)) do
                inputs[#inputs+1] = p
            end
        elseif e.file then
            inputs[#inputs+1] = e.file
        end
    end
    for _, e in ipairs(attribute.data or {}) do
        if e.dir then
            for _, p in ipairs(m.scan_inputs(e.dir, false)) do
                inputs[#inputs+1] = p
            end
        elseif e.file then
            inputs[#inputs+1] = e.file
        end
    end
    return inputs
end

return m
