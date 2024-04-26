---@meta luamake

---@class fs.path
---@class LmPath
---@alias LmStrlist any

---@class LmTargetAttri
---@field builddir string?
---@field bindir string?
---@field objdir string?
---@field rootdir string?
---@field workdir string?
---@field mode "debug" | "release"?
---@field crt "dynamic" | "static"?
---@field c "c89" | "c99" | "c11" | "c17" | "c23" | "clatest"?
---@field cxx "c++11" | "c++14" | "c++17" | "c++20" | "c++23" | "c++2a" | "c++2b" | "c++latest"?
---@field warnings "off" | "on" | "all" | "error" | "strict"?
---@field rtti "off" | "on"?
---@field visibility "hidden" | "default"?
---@field lto "off" | "on"?
---@field permissive "off" | "on"?
---@field includes LmStrlist?
---@field sysincludes LmStrlist?
---@field linkdirs LmStrlist?
---@field objdeps LmStrlist?
---@field defines LmStrlist?
---@field flags LmStrlist?
---@field ldflags LmStrlist?
---@field links LmStrlist?
---@field frameworks LmStrlist?
---@field deps LmStrlist?
---@field confs LmStrlist?
---@field sources LmStrlist?
---@field luaversion "lua53" | "lua54" | "lua55"?
---@field export_luaopen "off" | "on"?
---@field windows LmTargetAttri?
---@field linux LmTargetAttri?
---@field macos LmTargetAttri?
---@field ios LmTargetAttri?
---@field android LmTargetAttri?
---@field freebsd LmTargetAttri?
---@field openbsd LmTargetAttri?
---@field netbsd LmTargetAttri?
---@field msvc LmTargetAttri?
---@field gcc LmTargetAttri?
---@field clang LmTargetAttri?
---@field clang_cl LmTargetAttri?
---@field mingw LmTargetAttri?
---@field emcc LmTargetAttri?

---@class luamake: LmTargetAttri
---@field compile_commands string
---@field os string
---@field hostos string
---@field hostshell string
---@field compiler string
---@field cc string
---@field arch string
---@field [any] string | fs.path | LmPath
local lm = {}

---@param version string
function lm:required_version(version)
end

---@param path string | fs.path | LmPath
function lm:import(path)
end

---@param value string | fs.path
---@return LmPath
function lm:path(value)
end

---@param name string
---@return boolean
function lm:has(name)
end

---@param targets LmStrlist
function lm:default(targets)
end

---@class LmRuleAttri
---@field args LmStrlist
---@field description string?
---@field generator string?
---@field pool string?
---@field restat string?
---@field rspfile string?
---@field rspfile_content string?
---@field deps string?
---@field depfile string?

---@param attribute string
---@return fun(attribute: LmRuleAttri)
function lm:rule(attribute)
end

---@class LmPhonyAttri
---@field rootdir string?
---@field deps LmStrlist?
---@field inputs LmStrlist?
---@field outputs LmStrlist

---@param attribute string | LmPhonyAttri
---@return fun(attribute: LmPhonyAttri) ?
function lm:phony(attribute)
end

---@class LmRunluaAttri
---@field rootdir string?
---@field deps LmStrlist?
---@field inputs LmStrlist?
---@field outputs LmStrlist?
---@field script string
---@field args LmStrlist?

---@param attribute string | LmRunluaAttri
---@return fun(attribute: LmRunluaAttri) ?
function lm:runlua(attribute)
end

---@class LmBuildAttri
---@field rootdir string?
---@field deps LmStrlist?
---@field inputs LmStrlist?
---@field outputs LmStrlist
---@field rule string

---@param attribute string | LmBuildAttri
---@return fun(attribute: LmBuildAttri) ?
function lm:build(attribute)
end

---@class LmCopyAttri
---@field rootdir string?
---@field deps LmStrlist?
---@field inputs LmStrlist?
---@field outputs LmStrlist

---@param attribute string | LmCopyAttri
---@return fun(attribute: LmCopyAttri) ?
function lm:copy(attribute)
end

---@class LmMsvcCopyDllAttri
---@field rootdir string?
---@field deps LmStrlist?
---@field inputs LmStrlist?
---@field outputs LmStrlist
---@field type "vcrt" | "ucrt" | "asan"

---@param attribute string | LmMsvcCopyDllAttri
---@return fun(attribute: LmMsvcCopyDllAttri) ?
function lm:msvc_copydll(attribute)
end

---@param attribute string | LmTargetAttri
---@return fun(attribute: LmTargetAttri) ?
function lm:conf(attribute)
end

---@param name string
---@return fun(attribute: LmTargetAttri)
function lm:exe(name)
end

---@param name string
---@return fun(attribute: LmTargetAttri)
function lm:dll(name)
end

---@param name string
---@return fun(attribute: LmTargetAttri)
function lm:lib(name)
end

---@param name string
---@return fun(attribute: LmTargetAttri)
function lm:src(name)
end

lm.lua_exe = lm.exe
lm.lua_dll = lm.dll
lm.lua_lib = lm.lib
lm.lua_src = lm.src

lm.executable = lm.exe
lm.shared_library = lm.dll
lm.static_library = lm.lib
lm.source_set = lm.src

lm.lua_library = lm.lua_dll
lm.lua_source = lm.lua_src

return lm
