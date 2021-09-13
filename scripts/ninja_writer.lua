local fsutil = require "fsutil"

return function (filename)
    local ninja = require "ninja_syntax"(filename)
    local rule_name = {}
    local rule_command = {}
    local obj_name = {}
    local build_name = {}
    local phony = {}
    local default
    local last_rule
    local m = {}
    function m:rule(name, command, kwargs)
        if rule_command[command] then
            last_rule = rule_command[command]
            return
        end
        name = name:gsub('[^%w_]', '_')
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
        assert(build_name[output] == nil)
        build_name[output] = true
        ninja:build(output, last_rule, inputs, args)
    end
    function m:phony(output, inputs)
        assert(phony[output] == nil)
        phony[output] = inputs
        phony[#phony+1] = output
    end
    function m:default(targets)
        default = targets
    end
    function m:close()
        for _, out in ipairs(phony) do
            if not build_name[out] then
                ninja:build(out, 'phony', phony[out])
            end
        end
        if default then
            ninja:default(default)
        end
        ninja:close()
    end
    m.comment = ninja.comment
    m.variable = ninja.variable
    m.pool = ninja.pool
    m.variable = ninja.variable
    m.include = ninja.include
    m.subninja = ninja.subninja
    return m
end
