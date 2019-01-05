local lm = LUAMAKE

local r_loadfile = loadfile
local r_dofile = dofile

local function h_loadfile(filename)
    local f, err = r_loadfile(filename)
    if f then
        lm:add_script(filename)
    end
    return f, err
end

local function h_dofile(filename)
    local res = table.pack(r_dofile(filename))
    lm:add_script(filename)
    return table.unpack(res)
end

loadfile = h_loadfile
dofile = h_dofile

local function searchpath(name, path)
    local err = ''
    name = string.gsub(name, '%.', '/')
    for c in string.gmatch(path, '[^;]+') do
        local filename = string.gsub(c, '%?', name)
        local f = io.open(filename)
        if f then
            f:close()
            return filename, f
        end
        err = err .. ("\n\tno file '%s'"):format(filename)
    end
    return nil, err
end

local function searcher_lua(name)
    assert(type(package.path) == "string", "'package.path' must be a string")
    local filename, err1 = searchpath(name, package.path)
    if not filename then
        return err1
    end
    local f, err2 = r_loadfile(filename)
    if not f then
        error(("error loading module '%s' from file '%s':\n\t%s"):format(name, filename, err2))
    end
    lm:add_script(filename)
    return f, filename
end

package.searchers[2] = searcher_lua
