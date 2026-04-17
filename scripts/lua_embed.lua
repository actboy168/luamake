-- scripts/lua_embed.lua
-- Helper module for the lm:lua_embed target (registered in writer.lua).
-- Provides: config file generation and input file collection.

local fs       = require "bee.filesystem"
local fsutil   = require "fsutil"
local pathutil = require "pathutil"

local EMBED_DIR  = fsutil.join(package.procdir, "scripts", "lua_embed")
local GEN_SCRIPT = fsutil.join(EMBED_DIR, "lua_embed_gen.lua")
local BEE_GLUE   = fsutil.join(EMBED_DIR, "bee_glue.c")

local m = {}
m.GEN_SCRIPT = GEN_SCRIPT
m.BEE_GLUE   = BEE_GLUE

local function resolve_path(rootdir, p)
    return rootdir and pathutil.tostr(rootdir, p) or p
end

-- Recursively collect files under dirpath (lua_only filters to *.lua).
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

-- Serialize one entry { dir=, prefix=, pattern= } or { file=, name= }.
local function serialize_entry(e, rootdir)
    local parts = {}
    if e.dir then
        parts[#parts+1] = "dir = " .. string.format("%q", resolve_path(rootdir, e.dir))
        if e.prefix and e.prefix ~= "" then
            parts[#parts+1] = "prefix = " .. string.format("%q", e.prefix)
        end
        if e.pattern then
            parts[#parts+1] = "pattern = " .. string.format("%q", e.pattern)
        end
    elseif e.file then
        parts[#parts+1] = "file = " .. string.format("%q", resolve_path(rootdir, e.file))
        parts[#parts+1] = "name = " .. string.format("%q",
            assert(e.name, "entry with 'file' requires 'name'"))
    end
    return "                { " .. table.concat(parts, ", ") .. " },"
end

-- A group uses lua_mode (module-name scanning) when:
--   1. any dir-entry in the group has 'pattern', or
--   2. bee_glue is enabled and this is the 'preload' group
--      (the _PRELOAD hard-coded contract requires lua module names,
--       not raw filenames, as keys).
local function group_lua_mode(grp, grp_name, bee_glue)
    if bee_glue and grp_name == "preload" then return true end
    for _, e in ipairs(grp) do
        if type(e) == "table" and e.pattern then return true end
    end
    return false
end

-- Write config.lua for lua_embed_gen.lua.
-- Groups are derived from attribute.data string keys, sorted alphabetically.
-- Writes only when content changes (avoids unnecessary Ninja rebuilds).
function m.write_config(outdir, attribute, rootdir)
    fs.create_directories(outdir)
    local config_path = outdir .. "/config.lua"

    local lines = {
        "-- auto-generated lua_embed config",
        "return {",
        "    groups = {",
    }

    local data = attribute.data or {}

    -- Normalize bee_glue: accept only boolean / nil. Anything else (string,
    -- number, table, ...) is almost certainly a user mistake, so fail fast
    -- with a clear message instead of silently (mis)interpreting it.
    local bee_glue = attribute.bee_glue
    assert(bee_glue == nil or type(bee_glue) == "boolean",
        string.format("lua_embed: bee_glue must be a boolean, got %s", type(bee_glue)))

    -- When bee_glue is enabled, bee_glue.c references lua_embed.{main,preload,data}
    -- by name. These groups must be declared (even if empty) so the generated
    -- lua_embed_bundle struct contains the corresponding fields; otherwise
    -- bee_glue.c will fail to compile with "struct has no member" errors.
    if bee_glue == true then
        for _, required in ipairs({ "main", "preload", "data" }) do
            assert(type(data[required]) == "table",
                string.format(
                    "lua_embed: bee_glue requires group %q to be defined (use an empty table {} if unused)",
                    required))
        end
    end

    local order = {}
    for k in pairs(data) do
        if type(k) == "string" then order[#order+1] = k end
    end
    table.sort(order)

    for _, grp_name in ipairs(order) do
        local grp = data[grp_name]
        if type(grp) ~= "table" then goto continue end
        assert(grp_name:match("^[%a_][%w_]*$"),
            string.format("lua_embed group name %q is not a valid C identifier", grp_name))

        lines[#lines+1] = "        {"
        lines[#lines+1] = string.format("            name = %q,", grp_name)
        if grp.bytecode then
            lines[#lines+1] = "            bytecode = true,"
        end
        if group_lua_mode(grp, grp_name, bee_glue == true) then
            lines[#lines+1] = "            lua_mode = true,"
        end
        lines[#lines+1] = "            entries = {"
        for _, e in ipairs(grp) do
            if type(e) == "string" then
                local abspath = resolve_path(rootdir, e)
                local fname   = abspath:match("[^/\\]+$") or e
                lines[#lines+1] = "                { file = "
                    .. string.format("%q", abspath)
                    .. ", name = " .. string.format("%q", fname) .. " },"
            elseif type(e) == "table" then
                lines[#lines+1] = serialize_entry(e, rootdir)
            end
        end
        lines[#lines+1] = "            },"
        lines[#lines+1] = "        },"
        ::continue::
    end

    lines[#lines+1] = "    },"
    lines[#lines+1] = "}"
    lines[#lines+1] = ""

    local new_content = table.concat(lines, "\n")
    local old_f = io.open(config_path, "rb")
    if old_f then
        local old = old_f:read "*a"
        old_f:close()
        if old == new_content then return config_path end
    end

    local f = assert(io.open(config_path, "wb"), "cannot write config: " .. config_path)
    f:write(new_content)
    f:close()
    return config_path
end

-- Collect all input files for Ninja dependency tracking.
function m.collect_inputs(attribute, rootdir, config_path)
    local inputs = { GEN_SCRIPT }
    if config_path then
        inputs[#inputs+1] = config_path
    end

    local data = attribute.data or {}
    local bee_glue = attribute.bee_glue == true
    for grp_name, grp in pairs(data) do
        if type(grp_name) ~= "string" or type(grp) ~= "table" then goto continue end
        local lua_mode = group_lua_mode(grp, grp_name, bee_glue)
        for _, e in ipairs(grp) do
            if type(e) == "string" then
                inputs[#inputs+1] = resolve_path(rootdir, e)
            elseif type(e) == "table" then
                if e.dir then
                    local lua_only = lua_mode or (e.pattern ~= nil)
                    for _, p in ipairs(m.scan_inputs(resolve_path(rootdir, e.dir), lua_only)) do
                        inputs[#inputs+1] = p
                    end
                elseif e.file then
                    inputs[#inputs+1] = resolve_path(rootdir, e.file)
                end
            end
        end
        ::continue::
    end

    table.sort(inputs)
    return inputs
end

return m
