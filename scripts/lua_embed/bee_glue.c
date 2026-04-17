/* bee_glue.c -- static glue layer for bee.lua runtime
 * Not auto-generated; compiled together with the generated lua_embed.c.
 *
 * Hard-coded group conventions:
 *   lua_embed.preload  -- registered into package.preload
 *   lua_embed.main     -- first entry is the main script
 *   lua_embed.data     -- exposed via require("bee.embed")
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

/* ── preload ──────────────────────────────────────────────────────────────── */

/* Load a lua_embed_entry (passed as lightuserdata) and return a function. */
static int load_entry(lua_State* L) {
    const lua_embed_entry* e = (const lua_embed_entry*)lua_touserdata(L, 1);
    if (luaL_loadbuffer(L, e->data, e->size, e->name) != LUA_OK)
        return lua_error(L);
    return 1;
}

/* Lua factory: returns a package.preload-compatible loader closure. */
static const char preload_factory_src[] =
    "local load_entry, entry = ...\n"
    "return function(modname)\n"
    "    return load_entry(entry)(modname)\n"
    "end\n";

/* ── bee.embed ────────────────────────────────────────────────────────────── */

/* __index(t, name): look up name in lua_embed.data, cache result in t. */
static int l_embed_index(lua_State* L) {
    const char* name = luaL_checkstring(L, 2);
    const lua_embed_entry* e;
    for (e = lua_embed.data; e->name != NULL; e++) {
        if (strcmp(e->name, name) == 0) {
#if LUA_VERSION_NUM >= 505
            lua_pushexternalstring(L, e->data, e->size, NULL, NULL);
#else
            lua_pushlstring(L, e->data, e->size);
#endif
            /* cache: rawset(t, name, value) */
            lua_pushvalue(L, 2);
            lua_pushvalue(L, -2);
            lua_rawset(L, 1);
            return 1;
        }
    }
    lua_pushnil(L);
    return 1;
}

static int luaopen_bee_embed(lua_State* L) {
    lua_newtable(L);                        /* module table */
    lua_newtable(L);                        /* metatable */
    lua_pushcfunction(L, l_embed_index);
    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);
    return 1;
}

/* ── exported entry points ────────────────────────────────────────────────── */

LUA_EMBED_EXPORT int _bee_preload_module(lua_State* L) {
    const lua_embed_entry* e;
    luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
    lua_pushcfunction(L, luaopen_bee_embed);
    lua_setfield(L, -2, "bee.embed");
    if (luaL_loadbuffer(L, preload_factory_src, sizeof(preload_factory_src) - 1,
                        "=preload_factory") != LUA_OK)
        return lua_error(L);
    for (e = lua_embed.preload; e->name != NULL; e++) {
        lua_pushvalue(L, -1);               /* dup factory */
        lua_pushcfunction(L, load_entry);
        lua_pushlightuserdata(L, (void*)e);
        lua_call(L, 2, 1);                  /* -> loader closure */
        lua_setfield(L, -3, e->name);
    }
    lua_pop(L, 2);                          /* factory, _PRELOAD */
    return 0;
}

LUA_EMBED_EXPORT int _bee_main(lua_State* L) {
    const lua_embed_entry* m = lua_embed.main;
    if (m == NULL || m->name == NULL) {
        lua_pushstring(L, "lua_embed: no main entry configured");
        return lua_error(L);
    }
    _bee_preload_module(L);
    if (luaL_loadbuffer(L, m->data, m->size, m->name) != LUA_OK)
        return lua_error(L);
    if (lua_pcall(L, 0, 0, 0) != LUA_OK)
        return lua_error(L);
    return 0;
}
