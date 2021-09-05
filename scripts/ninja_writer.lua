local fs = require "bee.filesystem"

return function (filename)
    local ninja = require "ninja_syntax"(filename)
    local rule_name = {}
    local rule_command = {}
    local obj_name = {}
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
        output = output:replace_extension ".obj"
        local name = output:string()
        if obj_name[name] then
            local n = 1
            local stem = (output:parent_path() / output:stem()):string()
            repeat
                name = ("%s-%d.obj"):format(stem, n)
                n = n + 1
            until not obj_name[name]
        end
        obj_name[name] = true
        name = fs.path(name)
        ninja:build(name, last_rule, inputs, args)
        return name
    end
    function m:build(outputs, inputs, args)
        ninja:build(outputs, last_rule, inputs, args)
    end
    function m:phony(outputs, inputs, args)
        ninja:build(outputs, 'phony', inputs, args)
    end
    m.comment = ninja.comment
    m.variable = ninja.variable
    m.pool = ninja.pool
    m.variable = ninja.variable
    m.include = ninja.include
    m.subninja = ninja.subninja
    m.default = ninja.default
    m.close = ninja.close
    return m
end
