local fs = require "bee.filesystem"

local code_main <const> = [[

#include <lua.h>
#include <lauxlib.h>

#if defined(_WIN32)
#define LUA2C_API __declspec(dllexport)
#else
#define LUA2C_API
#endif

#define REG_SOURCE(module, name) \
    lua_pushlightuserdata(L, (void *)name); \
    lua_pushinteger(L, sizeof(name)); \
    lua_pushcclosure(L, get_module, 2); \
    lua_setfield(L, -2, #module);

static int get_module(lua_State *L) {
    const char* str = (const char *)lua_touserdata(L, lua_upvalueindex(1));
    size_t len = (size_t)lua_tointeger(L, lua_upvalueindex(2));
    if (luaL_loadbuffer(L, str, (size_t)len, str) != LUA_OK) {
        return lua_error(L);
    }
    lua_call(L, 0, 1);
    return 1;
}

]]

local code_bee_main <const> = [[
LUA2C_API int _bee_main(lua_State *L) {
    if (luaL_loadbuffer(L, (const char *)$main, sizeof($main), (const char *)$main) != LUA_OK) {
        return lua_error(L);
    }
    lua_call(L, 0, 0);
    return 0;
}

]]

local code_bee_preload_module <const> = [[
LUA2C_API int _bee_preload_module(lua_State *L) {
    luaL_getsubtable(L, LUA_REGISTRYINDEX, "_PRELOAD");
    $push
    lua_pop(L, 1);
    return 1;
}

]]

local code_reg <const> = [[REG_SOURCE($module, $name)]]

local code_bin <const> = [[
static const unsigned char $name[] = {
    $bytes
};
]]

local function readall(path)
    local file <close> = assert(io.open(path, "rb"))
    return file:read "a"
end

local function compile(content, symbol)
    local count = 0
    local function tohex(c)
        local b = string.format("0x%02x,", c:byte())
        count = count + 1
        if count == 16 then
            b = b.."\n    "
            count = 0
        end
        return b
    end
    local func = assert(load(content, "@"..symbol))
    local bin = string.dump(func)
    return bin:gsub(".", tohex)
end

local function fmtwrite(file, content, args)
    local output = content:gsub("$(%w+)", args)
    file:write(output)
    file:write "\n"
end

local function embed(file, list, lua)
    local cpp_symbol = "luasrc_"..lua.path:match("^(.+)%.lua$"):gsub("/", "_")
    if lua.symbol then
        list[#list+1] = code_reg:gsub("$(%w+)", {
            name = cpp_symbol,
            module = lua.symbol:match("^(.+)%.lua$"):gsub("/", "."),
        })
    end
    if lua.main then
        list.main = cpp_symbol
    end
    fmtwrite(file, code_bin, {
        name = cpp_symbol,
        bytes = compile(readall(lua.path), lua.path),
    })
end

local function lua2c(filename, luafiles)
    local file <close> = assert(io.open(filename, "wb"))

    local list = {}
    for _, lua in ipairs(luafiles) do
        embed(file, list, lua)
    end

    file:write(code_main)

    if list.main then
        fmtwrite(file, code_bee_main, {
            main = list.main,
        })
    end

    fmtwrite(file, code_bee_preload_module, {
        push = table.concat(list, "\n    "),
    })
end

local luafiles = {}
for path, status in fs.pairs_r "scripts" do
    if not status:is_directory() and path:extension() == ".lua" then
        local filename = path:string()
        local symbol = filename:sub(9)
        luafiles[#luafiles+1] = {
            path = filename,
            symbol = symbol,
        }
    end
end
luafiles[#luafiles+1] = {
    path = "main.lua",
    main = true,

}
lua2c("compile/lua/lua2c.c", luafiles)
