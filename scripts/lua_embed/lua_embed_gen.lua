-- lua_embed_gen.lua
-- Called by luamake runlua to generate lua_embed.c
-- Args: <config_file> <output_c>
--   config_file : Lua file (dofile), describes preload/data/main options
--   output_c    : path to write the generated lua_embed.c

local config_file = assert(arg[1], "arg[1]: config file required")
local output_c    = assert(arg[2], "arg[2]: output .c path required")

local cfg = assert(dofile(config_file))

-- bytecode=true 时使用 string.dump 生成字节码（体积更小、可隐藏源码），
-- 但要求 luamake 宿主 Lua 版本与目标 luaversion 一致。
-- 默认 false，嵌入源码以保证跨 Lua 版本兼容。
local use_bytecode = cfg.bytecode or false

-- ── helpers ──────────────────────────────────────────────────────────────────

local fs = require "bee.filesystem"

local function readfile(path)
    local f, err = io.open(path, "rb")
    if not f then error("cannot open: " .. path .. " (" .. tostring(err) .. ")") end
    local data = f:read("a")
    f:close()
    return data
end

local buf = {}
local function emit(s) buf[#buf+1] = s end
local function emit_flush(path)
    local out = assert(io.open(path, "wb"), "cannot write: " .. path)
    out:write(table.concat(buf))
    out:close()
    buf = {}
end

-- binary → C byte array initialiser  { 0xNN, 0xNN, ... }
-- 每 16 字节一组，用单次 string.format 批量格式化，直接 emit 输出
local fmt16 = ("0x%02x,"):rep(16) .. "\n    "
local function emit_c_bytes(data)
    local len = #data
    if len == 0 then
        -- 空数据时输出一个哨兵字节，避免生成空初始化列表（标准 C 不允许）
        -- 调用方记录的 size 仍为 0，运行时按长度读取不受影响
        emit("0x00\n    ")
        return
    end
    -- 完整的 16 字节行
    local n = len - len % 16
    for i = 1, n, 16 do
        emit(string.format(fmt16, data:byte(i, i + 15)))
    end
    -- 尾部不足 16 字节
    if n < len then
        local i = n + 1
        local rem = len - i + 1
        local fmt_tail = ("0x%02x,"):rep(rem) .. "\n    "
        emit(string.format(fmt_tail, data:byte(i, len)))
    end
end

local function to_c_ident(s)
    local ident = s:gsub("[^%w]", "_")
    if ident:match("^[0-9]") then
        ident = "_" .. ident
    end
    return ident
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

local function sorted_entries(dir)
    local entries = {}
    for entry in fs.pairs(dir) do
        entries[#entries+1] = entry
    end
    table.sort(entries, function(a, b)
        return a:filename():string() < b:filename():string()
    end)
    return entries
end

local function scan_preload_dir(dirpath, patterns, mod_prefix, result, seen)
    local root = fs.path(dirpath)
    if not fs.exists(root) then return end
    local function recurse(base, rel_base)
        for _, entry in ipairs(sorted_entries(base)) do
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
        for _, entry in ipairs(sorted_entries(base)) do
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

emit('/* Auto-generated by lua_embed_gen.lua -- DO NOT EDIT */\n')
emit('#include "lua_embed.h"\n\n')

-- preload entries: embed source code or bytecode depending on cfg.bytecode
local preload_idents = {}
local seen_idents = {}  -- 检测标识符冲突
for _, e in ipairs(preload_list) do
    local src       = readfile(e.path)
    local func, err = load(src, "@" .. e.path)
    if not func then error("syntax error in " .. e.path .. ": " .. tostring(err)) end
    local payload
    if use_bytecode then
        payload = string.dump(func)
    else
        payload = src
    end
    local id   = "lep_" .. to_c_ident(e.modname)
    if seen_idents[id] then
        error(string.format(
            "C identifier collision: %q and %q both map to %s",
            seen_idents[id], e.modname, id))
    end
    seen_idents[id] = e.modname
    preload_idents[#preload_idents+1] = { modname = e.modname, id = id, size = #payload }
    emit(string.format(
        "/* preload: %s */\nstatic const unsigned char %s[] = {\n    ",
        e.modname, id))
    emit_c_bytes(payload)
    emit("\n};\n\n")
end

-- data entries: raw bytes
local data_idents = {}
for _, e in ipairs(data_list) do
    local src = readfile(e.path)
    local id  = "led_" .. to_c_ident(e.name)
    if seen_idents[id] then
        error(string.format(
            "C identifier collision: %q and %q both map to %s",
            seen_idents[id], e.name, id))
    end
    seen_idents[id] = e.name
    data_idents[#data_idents+1] = { name = e.name, id = id, size = #src }
    emit(string.format(
        "/* data: %s */\nstatic const unsigned char %s[] = {\n    ",
        e.name, id))
    emit_c_bytes(src)
    emit("\n};\n\n")
end

-- preload table
emit("static const lua_embed_preload lua_embed_preload_table[] = {\n")
for _, e in ipairs(preload_idents) do
    emit(string.format(
        '    { %q, (const char*)%s, %d },\n', e.modname, e.id, e.size))
end
emit('    { NULL, NULL, 0 }\n};\n\n')

-- data table
emit("static const lua_embed_data lua_embed_data_table[] = {\n")
for _, e in ipairs(data_idents) do
    emit(string.format('    { %q, (const char*)%s, %d },\n', e.name, e.id, e.size))
end
emit('    { NULL, NULL, 0 }\n};\n\n')

-- main entry: embedded separately from data_table, accessible only via lua_embed_get_main()
local main_path = cfg.main
if main_path then
    local src = readfile(main_path)
    local func, err = load(src, "@" .. main_path)
    if not func then error("syntax error in " .. main_path .. ": " .. tostring(err)) end
    local payload
    if use_bytecode then
        payload = string.dump(func)
    else
        payload = src
    end
    emit(string.format(
        "/* main entry (private, not in data_table) */\nstatic const unsigned char lua_embed_main_data[] = {\n    "))
    emit_c_bytes(payload)
    emit("\n};\n\n")
    emit(string.format(
        'static const lua_embed_data lua_embed_main_entry = { "=main", (const char*)lua_embed_main_data, %d };\n\n',
        #payload))
end

-- lookup functions
emit([[
const lua_embed_preload* lua_embed_get_preload(void) {
    return lua_embed_preload_table;
}

const lua_embed_data* lua_embed_get_data(const char* name) {
    const lua_embed_data* e;
    for (e = lua_embed_data_table; e->name != NULL; e++) {
        if (strcmp(e->name, name) == 0) return e;
    }
    return NULL;
}
]])

if main_path then
    emit([[
const lua_embed_data* lua_embed_get_main(void) {
    return &lua_embed_main_entry;
}
]])
else
    emit([[
const lua_embed_data* lua_embed_get_main(void) {
    return NULL;
}
]])
end

emit_flush(output_c)
