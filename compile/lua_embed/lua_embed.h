#pragma once
/* lua_embed.h -- runtime interface for embedded Lua files
 * Generated data is linked into the executable.
 * Include this header in any C/C++ file that needs to access embedded modules.
 */

#include <stddef.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

/* A Lua module stored for injection into _PRELOAD.
 * 'name' is the require() key, e.g. "http.httpc".
 * 'data' points to Lua source code or bytecode; 'size' is its length in bytes.
 * By default source code is embedded for cross-Lua-version compatibility;
 * set bytecode=true in lm:lua_embed to embed bytecode instead (smaller, but
 * requires the host luamake Lua version to match the target luaversion).
 */
typedef struct lua_embed_preload {
    const char* name;
    const char* data;
    size_t      size;
} lua_embed_preload;

/* An arbitrary file stored as raw bytes (source or binary).
 * 'name' is the lookup key chosen by the user.
 * 'data' points to the raw content; 'size' is its length in bytes.
 */
typedef struct lua_embed_data {
    const char* name;
    const char* data;
    size_t      size;
} lua_embed_data;

/* Returns a NULL-terminated array of all preload entries. */
const lua_embed_preload* lua_embed_get_preload(void);

/* Finds a data entry by name; returns NULL if not found. */
const lua_embed_data* lua_embed_find(const char* name);

#ifdef __cplusplus
}
#endif
