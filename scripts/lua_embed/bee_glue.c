/* bee_glue.c -- static glue layer for bee.lua runtime
 * This file is NOT auto-generated; it is a static part of the lua_embed module.
 * It provides _bee_preload_module() and _bee_main() which rely on the
 * generated lua_embed.c for actual embedded data.
 */

#include "lua_embed.h"
#include <lua.h>
#include <lauxlib.h>

#if defined(_WIN32)
#  define LUA_EMBED_EXPORT __declspec(dllexport)
#else
#  define LUA_EMBED_EXPORT __attribute__((visibility("default")))
#endif

/* C helper: luaL_loadbuffer exposed as a Lua-callable function.
 * Signature: load_bytecode(lightuserdata buf, integer len, string name) -> function
 */
static int load_bytecode(lua_State* L) {
    const char* buf = (const char*)lua_touserdata(L, 1);
    size_t len = (size_t)lua_tointeger(L, 2);
    const char* name = lua_tostring(L, 3);
    if (luaL_loadbuffer(L, buf, len, name) != LUA_OK) return lua_error(L);
    return 1;
}

/* preload_loader: a fixed Lua factory function (always embedded as source).
 * Receives (load_bytecode, buf, len, name) and returns a closure suitable
 * for _PRELOAD[modname].
 */
static const char preload_loader_src[] =
    "local load_bytecode, buf, len, name = ...\n"
    "return function(modname)\n"
    "    local fn = load_bytecode(buf, len, name)\n"
    "    return fn(modname)\n"
    "end\n";

LUA_EMBED_EXPORT int _bee_preload_module(lua_State* L) {
    luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
    /* 在循环外加载一次 preload_loader factory 函数 */
    if (luaL_loadbuffer(L, preload_loader_src, sizeof(preload_loader_src) - 1, "=preload_loader") != LUA_OK)
        return lua_error(L);
    for (const lua_embed_preload* e = lua_embed_get_preload(); e->name != NULL; e++) {
        /* 复用栈顶的 factory 函数 */
        lua_pushvalue(L, -1);
        lua_pushcfunction(L, load_bytecode);
        lua_pushlightuserdata(L, (void*)e->data);
        lua_pushinteger(L, (lua_Integer)e->size);
        lua_pushstring(L, e->name);
        lua_call(L, 4, 1);  /* -> lua closure */
        lua_setfield(L, -3, e->name);
    }
    lua_pop(L, 2);  /* pop factory + _PRELOAD table */
    return 0;
}

LUA_EMBED_EXPORT int _bee_main(lua_State* L) {
    _bee_preload_module(L);
    const lua_embed_data* f = lua_embed_get_main();
    if (!f) {
        lua_pushstring(L, "lua_embed: no main entry configured");
        return lua_error(L);
    }
    if (luaL_loadbuffer(L, f->data, f->size, f->name) != LUA_OK)
        return lua_error(L);
    if (lua_pcall(L, 0, 0, 0) != LUA_OK)
        return lua_error(L);
    return 0;
}
