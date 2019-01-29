local util = require 'util'
local lm = require 'luamake'

local function create()
    local t = {}
    local globals = {}
    local function setter(_, k, v)
        globals[k] = v
    end
    local function getter(_, k)
        return globals[k]
    end
    local function accept(type, name, attribute)
        for k, v in pairs(globals) do
            if not attribute[k] then
                attribute[k] = v
            end
        end
        t[#t+1] = {type, name, attribute}
    end
    local m = setmetatable({}, {__index = getter, __newindex = setter})
    function m:shared_library(name)
        return function (attribute)
            accept('shared_library', name, attribute)
        end
    end
    function m:executable(name)
        return function (attribute)
            accept('executable', name, attribute)
        end
    end
    function m:lua_library(name)
        return function (attribute)
            accept('lua_library', name, attribute)
        end
    end
    function m:build(name)
        return function (attribute)
            accept('build', name, attribute)
        end
    end
    function m:phony(attribute)
        accept('phony', nil, attribute)
    end
    m.plat = util.plat
    return m, t, globals
end

return function()
    if not lm._export then
        lm._export, lm._export_targets, lm._export_globals = create()
    end
    return lm._export
end
