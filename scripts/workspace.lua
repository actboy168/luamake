local arguments = require "arguments"
local pathutil = require "pathutil"
local globals = require "globals"

local function create(workdir, parent, attri)
    local mt = {}
    function mt:__index(k)
        local v = attri[k]
        if v ~= nil then
            return v
        end
        return parent[k]
    end
    function mt:__newindex(k, v)
        if arguments.args[k] ~= nil then
            return
        end
        attri[k] = pathutil.accept(workdir, v)
    end
    if globals == attri then
        function mt:__pairs()
            return function (_, k)
                return next(attri, k)
            end
        end
        return setmetatable({ workdir = workdir }, mt)
    end
    function mt:__pairs()
        local selfpairs = true
        local mark = {}
        local parent_next, parent_state = pairs(parent)
        return function (_, k)
            if selfpairs then
                local newk, newv = next(attri, k)
                if newk ~= nil then
                    mark[newk] = true
                    return newk, newv
                end
                selfpairs = false
                k = nil
            end
            local newk = k
            local newv
            repeat
                newk, newv = parent_next(parent_state, newk)
            until newk == nil or not mark[newk]
            return newk, newv
        end
    end
    return setmetatable({ workdir = workdir }, mt)
end

return {
    create = create
}
