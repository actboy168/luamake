local fsutil = require "fsutil"
local ninja_syntax = require "ninja_syntax"

return function ()
    local ninja_head = ninja_syntax()
    local ninja_body = ninja_syntax()
    local ninja = ninja_head
    local rule_name = {}
    local rule_command = {}
    local obj_name = {}
    local builds = {}
    local phonys = {}
    local default
    local last_rule
    local m = {}
    function m:switch_head()
        ninja = ninja_head
    end

    function m:switch_body()
        ninja = ninja_body
    end

    function m:rule(name, command, kwargs)
        if rule_command[command] then
            last_rule = rule_command[command]
            return
        end
        name = name:gsub("[^%w_]", "_")
        if rule_name[name] then
            local newname = name.."_1"
            local i = 1
            while rule_name[newname] do
                i = i + 1
                newname = name.."_"..i
            end
            name = newname
        end
        rule_name[name] = true
        rule_command[command] = name
        last_rule = name
        ninja:rule(name, command, kwargs)
    end

    function m:set_rule(name)
        last_rule = name:gsub("[^%w_]", "_")
    end

    function m:build_obj(output, inputs, args)
        output = fsutil.join(fsutil.parent_path(output), fsutil.stem(output))
        local name = output..".obj"
        if obj_name[name] then
            local n = 1
            repeat
                name = ("%s-%d.obj"):format(output, n)
                n = n + 1
            until not obj_name[name]
        end
        obj_name[name] = true
        ninja:build(name, last_rule, inputs, args)
        return name
    end

    function m:build(output, inputs, args)
        builds[#builds+1] = output
        builds[output] = {
            rule = last_rule,
            inputs = inputs,
            args = args,
        }
    end

    function m:phony(output, inputs)
        assert(phonys[output] == nil)
        phonys[output] = inputs
        phonys[#phonys+1] = output
    end

    function m:default(targets)
        default = targets
    end

    function m:close(filename)
        for _, output in ipairs(builds) do
            local v = builds[output]
            if not v._written then
                v._written = true
                ninja_body:build(output, v.rule, v.inputs, v.args)
            end
        end
        for _, out in ipairs(phonys) do
            if not builds[out] then
                ninja_body:build(out, "phony", phonys[out])
            end
        end
        if default then
            ninja_body:default(default)
        end
        local f = assert(io.open(filename..".tmp", "wb"))
        f:write(ninja_head:close())
        f:write(ninja_body:close())
        f:close()
        os.remove(filename)
        os.rename(filename..".tmp", filename)
    end

    function m:comment(...)
        return ninja:comment(...)
    end

    function m:variable(...)
        return ninja:variable(...)
    end

    function m:pool(...)
        return ninja:pool(...)
    end

    function m:include(...)
        return ninja:include(...)
    end

    function m:subninja(...)
        return ninja:subninja(...)
    end

    return m
end
