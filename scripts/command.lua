local m = {}

local commands <const> = {
    build = true,
    clean = true,
    help = true,
    init = true,
    lua = true,
    rebuild = true,
    shell = true,
    test = true,
    version = true,
}

function m.has(name)
    return commands[name]
end

function m.run(name)
    assert(commands[name])
    require("command."..name)
end

function m.list()
    return commands
end

return m
