local fs = require "bee.filesystem"

local function sandbox_env(env, loadlua, openfile, preload)
    setmetatable(env, {__index=_G})

    local _PRELOAD = {}
    local _LOADED = preload or {}

    for _, name in ipairs {
        "_G",
        "package",
        "coroutine",
        "table",
        "io",
        "os",
        "string",
        "math",
        "utf8",
        "debug",
    } do
        _LOADED[name] = package.loaded[name]
    end

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
        local path, err1 = searchpath(name, env.package.path)
        if not path then
            return err1
        end
        local f, err2 = loadlua(path)
        if not f then
            error(("error loading module '%s' from file '%s':\n\t%s"):format(name, path, err2))
        end
        return f, path
    end

    local function searcher_c(name)
        assert(type(env.package.cpath) == "string", "'package.cpath' must be a string")
        local path, err1 = searchpath(name, env.package.cpath)
        if not path then
            return err1
        end
        name = name:gsub("%.", "_")
        name = name:gsub("[^%-]+%-", "")
        local res, err2 =  package.loadlib(path, "luaopen_" .. name)
        if not res then
            error(("error loading module '%s' from file '%s':\n\t%s"):format(name, path, err2))
        end
        return res, path
    end

    local function searcher_croot(name)
        assert(type(env.package.cpath) == "string", "'package.cpath' must be a string")
        if not name:find('.', 1, true) then
            return
        end
        local prefix = name:match "^[^%.]+"
        local path, err = searchpath(prefix, env.package.cpath)
        if not path then
            return err
        end
        name = name:gsub("%.", "_")
        name = name:gsub("[^%-]+%-", "")
        local res, err2 =  package.loadlib(path, "luaopen_" .. name)
        if not res then
            error(("error loading module '%s' from file '%s':\n\t%s"):format(name, path, err2))
        end
        return res, path
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
        if name == 'bee' or name:sub(1,4) == 'bee.' then
            return require(name)
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
        config = package.config,
        loaded = _LOADED,
        preload = _PRELOAD,
        path = '?.lua',
        cpath = package.cpath,
        searchpath = searchpath,
        loadlib = package.loadlib,
        searchers = {
            searcher_preload,
            searcher_lua,
            searcher_c,
            searcher_croot,
        }
    }

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

return function (root, main, io_open, preload)
    local function absolute(name)
        return fs.absolute(fs.path(name), fs.path(root)):string()
    end
    local function openfile(name, mode)
        return io_open(absolute(name), mode)
    end
    local env = {}
    local function loadlua(name)
        local f, err = openfile(name, 'r')
        if f then
            if '#' == f:read(1) then
                f:read "l"
            else
                f:seek "set"
            end
            local str = f:read 'a'
            f:close()
            return load(str, '@' .. absolute(name), 't', env)
        end
        return nil, err
    end
    local init, err = loadlua(main)
    if not init then
        return nil, err
    end
    debug.setupvalue(init, 1, sandbox_env(env, loadlua, openfile, preload))
    return init
end
