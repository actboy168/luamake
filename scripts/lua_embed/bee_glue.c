/* bee_glue.c -- static glue layer for bee.lua runtime
 * This file is NOT auto-generated; it is a static part of the lua_embed module.
 * It provides _bee_preload_module() and _bee_main() which rely on the
 * generated lua_embed.c for actual embedded data.
 */

#include "lua_embed_data.h"
#include <lua.h>
#include <lauxlib.h>
#include <string.h>

#if defined(_WIN32)
#  define LUA_EMBED_EXPORT __declspec(dllexport)
#else
#  define LUA_EMBED_EXPORT __attribute__((visibility("default")))
#endif

/* C helper: load a lua_embed_entry entry from a lightuserdata pointer.
 * Signature: load_bytecode(lightuserdata entry) -> function
 */
static int load_bytecode(lua_State* L) {
    const lua_embed_entry* e = (const lua_embed_entry*)lua_touserdata(L, 1);
    if (luaL_loadbuffer(L, e->data, e->size, e->name) != LUA_OK) return lua_error(L);
    return 1;
}

/* preload_loader: a fixed Lua factory function (always embedded as source).
 * Receives (load_bytecode, entry) and returns a closure suitable
 * for _PRELOAD[modname].
 */
static const char preload_loader_src[] =
    "local load_bytecode, entry = ...\n"
    "return function(modname)\n"
    "    return load_bytecode(entry)(modname)\n"
    "end\n";

/* bee.embed module: exposes embedded data files to Lua.
 * require("bee.embed") returns a table.  Indexing it by name returns the
 * embedded string (or nil).  The result is cached in the table itself via
 * rawset so the __index metamethod fires at most once per key.
 */
static int l_embed_index(lua_State* L) {
    /* L: table, name */
    const char* name = luaL_checkstring(L, 2);
    const lua_embed_entry* d;
    for (d = lua_embed_data_table; d->name != NULL; d++) {
        if (strcmp(d->name, name) == 0) break;
    }
    if (d->name == NULL) {
        lua_pushnil(L);
        return 1;
    }
#if LUA_VERSION_NUM >= 505
    /* Zero-copy: data arrays end with a sentinel '\0' (see lua_embed_gen.lua).
     * falloc=NULL tells Lua the buffer is static and must not be freed. */
    lua_pushexternalstring(L, d->data, d->size, NULL, NULL);
#else
    lua_pushlstring(L, d->data, d->size);
#endif
    /* cache: rawset(table, name, string) so __index won't fire again */
    lua_pushvalue(L, 2);  /* key */
    lua_pushvalue(L, -2); /* value */
    lua_rawset(L, 1);
    return 1;
}

static int luaopen_bee_embed(lua_State* L) {
    lua_newtable(L);            /* module table (acts as its own cache) */
    lua_newtable(L);            /* metatable */
    lua_pushcfunction(L, l_embed_index);
    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);
    return 1;
}

LUA_EMBED_EXPORT int _bee_preload_module(lua_State* L) {
    const lua_embed_entry* e;
    luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
    /* Register bee.embed */
    lua_pushcfunction(L, luaopen_bee_embed);
    lua_setfield(L, -2, "bee.embed");
    /* Load the preload_loader factory once, outside the loop */
    if (luaL_loadbuffer(L, preload_loader_src, sizeof(preload_loader_src) - 1, "=preload_loader") != LUA_OK)
        return lua_error(L);
    for (e = lua_embed_preload_table; e->name != NULL; e++) {
        /* Reuse the factory function at the top of the stack */
        lua_pushvalue(L, -1);
        lua_pushcfunction(L, load_bytecode);
        lua_pushlightuserdata(L, (void*)e);
        lua_call(L, 2, 1);  /* -> lua closure */
        lua_setfield(L, -3, e->name);
    }
    lua_pop(L, 2);  /* pop factory + _PRELOAD table */
    return 0;
}

LUA_EMBED_EXPORT int _bee_main(lua_State* L) {
    _bee_preload_module(L);
    if (!lua_embed_main_entry.name) {
        lua_pushstring(L, "lua_embed: no main entry configured");
        return lua_error(L);
    }
    if (luaL_loadbuffer(L, lua_embed_main_entry.data, lua_embed_main_entry.size, lua_embed_main_entry.name) != LUA_OK)
        return lua_error(L);
    if (lua_pcall(L, 0, 0, 0) != LUA_OK)
        return lua_error(L);
    return 0;
}
