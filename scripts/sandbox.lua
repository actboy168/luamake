local function sandbox_env(loadlua, openfile, preload)
    local env = setmetatable({}, {__index=_G})
    local _PRELOAD = {}
    local _LOADED = preload or {}

    local function searchpath(name, path)
        local err = ''
        name = string.gsub(name, '%.', '/')
        for c in string.gmatch(path, '[^;]+') do
            local filename = string.gsub(c, '%?', name)
            local f = openfile(filename)
            if f then
                f:close()
                return filename
            end
            err = err .. ("\n\tno file '%s'"):format(filename)
        end
        return nil, err
    end

    local function searcher_preload(name)
        assert(type(_PRELOAD) == "table", "'package.preload' must be a table")
        if _PRELOAD[name] == nil then
            return ("\n\tno field package.preload['%s']"):format(name)
        end
        return _PRELOAD[name]
    end

    local function searcher_lua(name)
        assert(type(env.package.path) == "string", "'package.path' must be a string")
        local filename, err1 = searchpath(name, env.package.path)
        if not filename then
            return err1
        end
        local f, err2 = loadlua(filename)
        if not f then
            error(("error loading module '%s' from file '%s':\n\t%s"):format(name, filename, err2))
        end
        return f, filename
    end

    local function require_load(name)
        local msg = ''
        local _SEARCHERS = env.package.searchers
        assert(type(_SEARCHERS) == "table", "'package.searchers' must be a table")
        for _, searcher in ipairs(_SEARCHERS) do
            local f, extra = searcher(name)
            if type(f) == 'function' then
                return f, extra
            elseif type(f) == 'string' then
                msg = msg .. f
            end
        end
        error(("module '%s' not found:%s"):format(name, msg))
    end

    function env.require(name)
        assert(type(name) == "string", ("bad argument #1 to 'require' (string expected, got %s)"):format(type(name)))
        local p = _LOADED[name]
        if p ~= nil then
            return p
        end
        local init, extra = require_load(name)
        debug.setupvalue(init, 1, env)
        local res = init(name, extra)
        if res ~= nil then
            _LOADED[name] = res
        end
        if _LOADED[name] == nil then
            _LOADED[name] = true
        end
        return _LOADED[name]
    end

    env.package = {
        config = table.concat({"/",";","?","!","-"}, "\n"),
        loaded = _LOADED,
        preload = _PRELOAD,
        path = '?.lua',
        searchpath = searchpath,
        searchers = {}
    }
    for i, searcher in ipairs(package.searchers) do
        env.package.searchers[i] = searcher
    end
    env.package.searchers[1] = searcher_preload
    env.package.searchers[2] = searcher_lua

    function env.loadfile(filename)
        return loadlua(filename)
    end

    function env.dofile(filename)
        local f, err = loadlua(filename)
        if not f then
            error(err)
        end
        return f()
    end

    return env
end

return function(root, main, io_open, preload)
    local function openfile(name, mode)
        return io_open(root .. '/' .. name, mode)
    end
    local function loadlua(name)
        local f, err = openfile(name, 'r')
        if f then
            local str = f:read 'a'
            f:close()
            return load(str, '@' .. root .. '/' .. name)
        end
        return nil, err
    end
    local init, err = loadlua(main)
    if not init then
        return nil, err
    end
    debug.setupvalue(init, 1, sandbox_env(loadlua, openfile, preload))
    return init
end
