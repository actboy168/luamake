-- lua_embed_gen.lua
-- Called by luamake runlua to generate lua_embed.c (and optionally bee_glue.c)
-- Args: <config_file> <output_c> [output_bee_glue_c]
--   config_file      : Lua file (dofile), describes preload/data/glue options
--   output_c         : path to write the generated lua_embed.c
--   output_bee_glue_c: (optional) path to write bee_glue.c when glue="bee"

local config_file      = assert(arg[1], "arg[1]: config file required")
local output_c         = assert(arg[2], "arg[2]: output .c path required")
local output_bee_glue  = arg[3]  -- optional

local cfg = assert(dofile(config_file))

-- ── helpers ──────────────────────────────────────────────────────────────────

local fs = require "bee.filesystem"

local function readfile(path)
    local f, err = io.open(path, "rb")
    if not f then error("cannot open: " .. path .. " (" .. tostring(err) .. ")") end
    local data = f:read("a")
    f:close()
    return data
end

local function writefile(path, data)
    local out = assert(io.open(path, "wb"), "cannot write: " .. path)
    out:write(data)
    out:close()
end

-- binary → C byte array initialiser  { 0xNN, 0xNN, ... }
local function to_c_bytes(data)
    local count = 0
    local parts = {}
    for i = 1, #data do
        parts[i] = string.format("0x%02x,", data:byte(i))
        count = count + 1
        if count == 16 then
            parts[i] = parts[i] .. "\n    "
            count = 0
        end
    end
    return table.concat(parts)
end

local function to_c_ident(s)
    return s:gsub("[^%w]", "_")
end

-- ── scan a directory and collect preload entries ──────────────────────────────
-- pattern examples: "?.lua" "?/init.lua"
-- returns list of { modname, abspath }

local function match_pattern(rel, pat)
    -- pat uses '?' as placeholder for module path (slashes), suffix is literal
    local prefix, suffix = pat:match("^(.-)%?(.*)$")
    if not prefix or not suffix then return nil end
    -- rel must start with prefix and end with suffix
    if rel:sub(1, #prefix) ~= prefix then return nil end
    if rel:sub(-#suffix) ~= suffix and #suffix > 0 then return nil end
    local mid = rel:sub(#prefix + 1, #suffix > 0 and -#suffix - 1 or #rel)
    -- mid is the '?' part, e.g. "http/httpc" or "tui"
    return mid:gsub("/", ".")
end

local function scan_preload_dir(dirpath, patterns, mod_prefix, result, seen)
    local root = fs.path(dirpath)
    if not fs.exists(root) then return end
    local function recurse(base, rel_base)
        for entry in fs.pairs(base) do
            local name = entry:filename():string()
            local rel  = rel_base ~= "" and (rel_base .. "/" .. name) or name
            if fs.is_directory(entry) then
                recurse(entry, rel)
            elseif name:match("%.lua$") then
                local modname
                for _, pat in ipairs(patterns) do
                    local m = match_pattern(rel, pat)
                    if m then
                        modname = (mod_prefix ~= "" and (mod_prefix .. "." .. m) or m)
                        break
                    end
                end
                if modname then
                    local abspath = entry:string():gsub("\\", "/")
                    if seen[modname] then
                        io.write(string.format(
                            "[lua_embed] warning: preload %q overridden by %s\n",
                            modname, abspath))
                    end
                    seen[modname] = true
                    result[#result+1] = { modname = modname, path = abspath }
                else
                    io.write(string.format(
                        "[lua_embed] warning: %s/%s does not match any pattern, skipped\n",
                        dirpath, rel))
                end
            end
        end
    end
    recurse(root, "")
end

-- ── collect preload entries ───────────────────────────────────────────────────

local preload_map   = {}  -- modname → path  (for override detection)
local preload_list  = {}  -- ordered { modname, path }

for _, entry in ipairs(cfg.preload or {}) do
    local patterns_str = entry.pattern or "?.lua;?/init.lua"
    local patterns = {}
    for p in patterns_str:gmatch("[^;]+") do
        patterns[#patterns+1] = p
    end
    local mod_prefix = entry.prefix or ""

    if entry.dir then
        local tmp_seen = {}
        local tmp = {}
        scan_preload_dir(entry.dir, patterns, mod_prefix, tmp, tmp_seen)
        for _, e in ipairs(tmp) do
            if preload_map[e.modname] then
                io.write(string.format(
                    "[lua_embed] warning: preload %q overridden by %s\n",
                    e.modname, e.path))
                -- 更新已有条目的路径
                for _, existing in ipairs(preload_list) do
                    if existing.modname == e.modname then
                        existing.path = e.path
                        break
                    end
                end
            else
                preload_list[#preload_list+1] = e
            end
            preload_map[e.modname] = e.path
        end
    elseif entry.file then
        local modname = assert(entry.name,
            "preload entry with 'file' requires 'name': " .. tostring(entry.file))
        local abspath = entry.file:gsub("\\", "/")
        if preload_map[modname] then
            io.write(string.format(
                "[lua_embed] warning: preload %q overridden by %s\n",
                modname, abspath))
            for _, e in ipairs(preload_list) do
                if e.modname == modname then e.path = abspath; break end
            end
        else
            preload_list[#preload_list+1] = { modname = modname, path = abspath }
        end
        preload_map[modname] = abspath
    end
end

-- ── collect data entries ──────────────────────────────────────────────────────

local data_list = {}  -- { name, path }

local function scan_data_dir(dirpath, prefix, result)
    local root = fs.path(dirpath)
    if not fs.exists(root) then return end
    local function recurse(base, rel_base)
        for entry in fs.pairs(base) do
            local fname = entry:filename():string()
            local rel   = rel_base ~= "" and (rel_base .. "/" .. fname) or fname
            if fs.is_directory(entry) then
                recurse(entry, rel)
            else
                result[#result+1] = {
                    name = prefix .. rel,
                    path = entry:string():gsub("\\", "/"),
                }
            end
        end
    end
    recurse(root, "")
end

for _, entry in ipairs(cfg.data or {}) do
    if entry.dir then
        scan_data_dir(entry.dir, entry.prefix or "", data_list)
    elseif entry.file then
        data_list[#data_list+1] = {
            name = assert(entry.name,
                "data entry with 'file' requires 'name': " .. tostring(entry.file)),
            path = entry.file:gsub("\\", "/"),
        }
    end
end

-- ── ensure output directory exists ───────────────────────────────────────────

local outdir = output_c:match("^(.*)/[^/]+$")
if outdir then fs.create_directories(outdir) end

-- ── generate .c file ─────────────────────────────────────────────────────────

local buf = {}
local function emit(...) buf[#buf+1] = table.concat({...}) end

emit('/* Auto-generated by lua_embed_gen.lua -- DO NOT EDIT */\n')
emit('#include "lua_embed.h"\n\n')

-- preload entries: compiled to bytecode
local preload_idents = {}
for _, e in ipairs(preload_list) do
    local src  = readfile(e.path)
    local func = assert(load(src, "@" .. e.path), "syntax error in " .. e.path)
    local bc   = string.dump(func)
    local id   = "lep_" .. to_c_ident(e.modname)
    preload_idents[#preload_idents+1] = { modname = e.modname, id = id, size = #bc }
    emit(string.format(
        "/* preload: %s */\nstatic const unsigned char %s[] = {\n    %s\n};\n\n",
        e.modname, id, to_c_bytes(bc)))
end

-- data entries: raw bytes
local data_idents = {}
for _, e in ipairs(data_list) do
    local src = readfile(e.path)
    local id  = "led_" .. to_c_ident(e.name)
    data_idents[#data_idents+1] = { name = e.name, id = id, size = #src }
    emit(string.format(
        "/* data: %s */\nstatic const unsigned char %s[] = {\n    %s\n};\n\n",
        e.name, id, to_c_bytes(src)))
end

-- preload table
emit("static const lua_embed_preload lua_embed_preload_table[] = {\n")
for _, e in ipairs(preload_idents) do
    emit(string.format(
        '    { "%s", (const char*)%s, %d },\n', e.modname, e.id, e.size))
end
emit('    { NULL, NULL, 0 }\n};\n\n')

-- data table
emit("static const lua_embed_data lua_embed_data_table[] = {\n")
for _, e in ipairs(data_idents) do
    emit(string.format('    { "%s", (const char*)%s, %d },\n', e.name, e.id, e.size))
end
emit('    { NULL, NULL, 0 }\n};\n\n')

-- lookup functions
emit([[
const lua_embed_preload* lua_embed_get_preload(void) {
    return lua_embed_preload_table;
}

const lua_embed_data* lua_embed_find(const char* name) {
    for (const lua_embed_data* e = lua_embed_data_table; e->name != NULL; e++) {
        if (strcmp(e->name, name) == 0) return e;
    }
    return NULL;
}
]])

writefile(output_c, table.concat(buf))

-- ── optional bee.lua glue layer ───────────────────────────────────────────────
if output_bee_glue then
    local main_key = cfg.main
    -- When main_key is absent or no_main=true, only _bee_preload_module is emitted.
    -- The caller is responsible for providing _bee_main.
    local emit_main = main_key ~= nil and not cfg.no_main

    local gdir = output_bee_glue:match("^(.*)/[^/]+$")
    if gdir then fs.create_directories(gdir) end

    local gb = {}
    local function gemit(...) gb[#gb+1] = table.concat({...}) end

    gemit('/* Auto-generated bee.lua glue -- DO NOT EDIT */\n')
    gemit('#include "lua_embed.h"\n')
    gemit('#include <lua.h>\n')
    gemit('#include <lauxlib.h>\n\n')
    gemit('#if defined(_WIN32)\n')
    gemit('#  define LUA_EMBED_EXPORT __declspec(dllexport)\n')
    gemit('#else\n')
    gemit('#  define LUA_EMBED_EXPORT __attribute__((visibility("default")))\n')
    gemit('#endif\n\n')

    gemit([[
static int preload_loader(lua_State* L) {
    const char* buf = (const char*)lua_touserdata(L, lua_upvalueindex(1));
    size_t len = (size_t)lua_tointeger(L, lua_upvalueindex(2));
    if (luaL_loadbuffer(L, buf, len, buf) != LUA_OK) return lua_error(L);
    lua_call(L, 0, 1);
    return 1;
}

]])

    gemit('LUA_EMBED_EXPORT int _bee_preload_module(lua_State* L) {\n')
    gemit('    luaL_getsubtable(L, LUA_REGISTRYINDEX, "_PRELOAD");\n')
    gemit('    for (const lua_embed_preload* e = lua_embed_get_preload(); e->name != NULL; e++) {\n')
    gemit('        lua_pushlightuserdata(L, (void*)e->data);\n')
    gemit('        lua_pushinteger(L, (lua_Integer)e->size);\n')
    gemit('        lua_pushcclosure(L, preload_loader, 2);\n')
    gemit('        lua_setfield(L, -2, e->name);\n')
    gemit('    }\n')
    gemit('    lua_pop(L, 1);\n')
    gemit('    return 0;\n')
    gemit('}\n\n')

    if emit_main then
        gemit('LUA_EMBED_EXPORT int _bee_main(lua_State* L) {\n')
        gemit('    _bee_preload_module(L);\n')
        gemit(string.format('    const lua_embed_data* f = lua_embed_find(%q);\n', main_key))
        gemit('    if (!f) {\n')
        gemit(string.format(
            '        lua_pushstring(L, "lua_embed: entry not found: %s");\n', main_key))
        gemit('        return lua_error(L);\n')
        gemit('    }\n')
        gemit('    if (luaL_loadbuffer(L, f->data, f->size, f->name) != LUA_OK)\n')
        gemit('        return lua_error(L);\n')
        gemit('    if (lua_pcall(L, 0, 0, 0) != LUA_OK)\n')
        gemit('        return lua_error(L);\n')
        gemit('    return 0;\n')
        gemit('}\n')
    end

    writefile(output_bee_glue, table.concat(gb))
end
