-- lua_embed_gen.lua
-- Called by luamake runlua to generate lua_embed.c
-- Args: <config_file> <output_c>
--   config_file : Lua file (dofile), describes data groups
--   output_c    : path to write the generated lua_embed.c

local config_file = assert(arg[1], "arg[1]: config file required")
local output_c    = assert(arg[2], "arg[2]: output .c path required")
-- lua_embed_data.h is written to the same directory as output_c
local output_h    = output_c:match("^(.*)/[^/]+$") .. "/lua_embed_data.h"

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

-- validate that a group name is a valid C identifier
local function check_c_ident(name)
    assert(name:match("^[%a_][%w_]*$"),
        string.format("group name %q is not a valid C identifier", name))
end

-- ── scan a directory and collect preload entries ──────────────────────────────
-- pattern examples: "?.lua" "?/init.lua"
-- returns list of { modname, abspath }

local function match_pattern(rel, pat)
    local prefix, suffix = pat:match("^(.-)%?(.*)$")
    if not prefix or not suffix then return nil end
    if rel:sub(1, #prefix) ~= prefix then return nil end
    if rel:sub(-#suffix) ~= suffix and #suffix > 0 then return nil end
    local mid = rel:sub(#prefix + 1, #suffix > 0 and -#suffix - 1 or #rel)
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

local function scan_lua_dir(dirpath, patterns, mod_prefix, result, seen)
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
                            "[lua_embed] warning: %q overridden by %s\n",
                            modname, abspath))
                    end
                    seen[modname] = true
                    result[#result+1] = { name = modname, path = abspath }
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

-- ── process groups ────────────────────────────────────────────────────────────
-- cfg.groups is an ordered list of { name, bytecode, entries[] }
-- each entry is { dir=, prefix=, pattern= } or { file=, name= }

local function collect_group_files(group_cfg)
    -- group_cfg.entries is the array part of the group table from config
    -- group_cfg.lua_only: true means scan only .lua files (preload-style naming)
    -- For simplicity: if entry has pattern field or dir with lua files → use lua scan
    -- In the new unified model every entry is raw bytes; naming is caller's concern.
    -- We use two sub-helpers based on whether 'pattern' key is present.
    local result = {}
    local seen   = {}
    for _, e in ipairs(group_cfg.entries) do
        if e.dir then
            if e.pattern ~= nil or group_cfg.lua_mode then
                -- lua module scan
                local patterns_str = e.pattern or "?.lua;?/init.lua"
                local patterns = {}
                for p in patterns_str:gmatch("[^;]+") do
                    patterns[#patterns+1] = p
                end
                scan_lua_dir(e.dir, patterns, e.prefix or "", result, seen)
            else
                scan_data_dir(e.dir, e.prefix or "", result)
            end
        elseif e.file then
            result[#result+1] = {
                name = assert(e.name, "entry with 'file' requires 'name'"),
                path = e.file,
            }
        end
    end
    return result
end

-- ── ensure output directory exists ───────────────────────────────────────────

local outdir = output_c:match("^(.*)/[^/]+$")
if outdir then fs.create_directories(outdir) end

-- ── generate .c file ─────────────────────────────────────────────────────────

emit('/* Auto-generated by lua_embed_gen.lua -- DO NOT EDIT */\n')
emit('#include "lua_embed_data.h"\n\n')

-- group_idents: ordered list of { name, entries_id }
local group_idents = {}
local seen_c_idents = {}

for _, grp in ipairs(cfg.groups) do
    local grp_name  = grp.name
    check_c_ident(grp_name)
    local use_bytecode = grp.bytecode or false
    local lua_mode     = grp.lua_mode or false

    local files = collect_group_files({ entries = grp.entries, lua_mode = lua_mode })

    -- per-entry byte arrays
    local entry_idents = {}
    for _, f in ipairs(files) do
        local src = readfile(f.path)
        local payload
        if use_bytecode then
            local func, err = load(src, "@" .. f.path)
            if not func then error("syntax error in " .. f.path .. ": " .. tostring(err)) end
            payload = string.dump(func)
        else
            payload = src
        end
        local id = "le_" .. to_c_ident(grp_name) .. "_" .. to_c_ident(f.name)
        if seen_c_idents[id] then
            error(string.format(
                "C identifier collision: %q and %q both map to %s",
                seen_c_idents[id], f.name, id))
        end
        seen_c_idents[id] = f.name
        entry_idents[#entry_idents+1] = { name = f.name, id = id, size = #payload }
        emit(string.format(
            "/* %s: %s */\nstatic const unsigned char %s[] = {\n    ",
            grp_name, f.name, id))
        emit_c_bytes(payload)
        -- sentinel '\0' for lua_pushexternalstring (lua 5.5+)
        emit("0x00\n};\n\n")
    end

    -- entries array for this group
    local entries_id = "lg_entries_" .. to_c_ident(grp_name)
    emit(string.format("static const lua_embed_entry %s[] = {\n", entries_id))
    for _, e in ipairs(entry_idents) do
        emit(string.format('    { %q, (const char*)%s, %d },\n', e.name, e.id, e.size))
    end
    emit('    { NULL, NULL, 0 }\n};\n\n')

    group_idents[#group_idents+1] = { name = grp_name, entries_id = entries_id }
end

-- bundle struct instance
emit("const lua_embed_bundle lua_embed = {\n")
for _, g in ipairs(group_idents) do
    emit(string.format("    /* .%s */ %s,\n", g.name, g.entries_id))
end
emit("};\n")

emit_flush(output_c)

-- ── generate lua_embed_data.h ─────────────────────────────────────────────────

local hbuf = {}
local function hemit(s) hbuf[#hbuf+1] = s end
hemit('/* Auto-generated by lua_embed_gen.lua -- DO NOT EDIT */\n')
hemit('#pragma once\n')
hemit('#include <stddef.h>\n\n')
hemit('#ifdef __cplusplus\nextern "C" {\n#endif\n\n')

hemit('typedef struct lua_embed_entry {\n')
hemit('    const char* name;\n')
hemit('    const char* data;\n')
hemit('    size_t      size;\n')
hemit('} lua_embed_entry;\n\n')

hemit('typedef struct lua_embed_bundle {\n')
for _, g in ipairs(group_idents) do
    hemit(string.format('    const lua_embed_entry* %s; /* NULL-terminated */\n', g.name))
end
hemit('} lua_embed_bundle;\n\n')

hemit('extern const lua_embed_bundle lua_embed;\n')
hemit('\n#ifdef __cplusplus\n}\n#endif\n')

local hout = assert(io.open(output_h, "wb"), "cannot write: " .. output_h)
hout:write(table.concat(hbuf))
hout:close()
