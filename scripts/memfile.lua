
local mt = {}
mt.__index = mt

function mt:write(str)
    table.insert(self._buf, str)
end
function mt:flush()
end
function mt:close()
    assert(
        assert(
            io.open(self._filename, 'w')
        ):write(table.concat(self._buf))
    ):close()
end

return function (filename)
    local f, err = io.open(filename, 'w')
    if not f then
        return nil, err
    end
    f:close()
    os.remove(filename)
    return setmetatable({
        _filename = filename,
        _buf = {}
    }, mt)
end

