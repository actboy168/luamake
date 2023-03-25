local function trim(str)
	return str:gsub("^%s*(.-)%s*$", "%1")
end

local function parse(str)
    local res = {}
    for s in str:gmatch '[^;]+' do
        local r = {}
        s:gsub('[^:]+', function (w) r[#r+1] = w end)
        if r[1] and r[2] then
            res[trim(r[1])] = trim(r[2])
        end
    end
    return res
end

local ansi16 = {
    black	= 30,
    red	    = 31,
    green	= 32,
    yellow	= 33,
    blue	= 34,
    magenta	= 35,
    cyan	= 36,
    white	= 37,
}

local function escape_code(option)
    if type(option) == 'string' then
        option = parse(option)
    end
    local escape = ''
    if option.color then
        local v = option.color
        local color = ansi16[v:lower()]
        if color then
            escape = escape .. ';' .. (color + 60)
        end
    end
    if option.background then
        local v = option.background
        local color = ansi16[v:lower()]
        if color then
            escape = escape .. ';' .. (color + 10)
        end
    end
    if escape == '' then
        return  '\x1b[0m'
    end
    return  '\x1b[' .. escape:sub(2) .. 'm'
end

local function fmt(...)
    local n = 0
    local args = table.pack(...)
    local rets = {}
    while n < args.n do
        n = n + 1
        rets[#rets+1] = args[n]:gsub('{([0-9a-zA-Z]*)}', function (w)
            n = n + 1
            if n > args.n then
                return
            end
            if w == 'c' then
                return escape_code(args[n])
            end
        end)
    end
    return table.unpack(rets)
end

local function log(...)
    print(fmt(...))
end

local function set(option)
    io.write(escape_code(option))
end

return {
    fmt = fmt,
    log = log,
    set = set,
}
