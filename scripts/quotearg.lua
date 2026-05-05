return function (s)
    if #s == 0 then
        return '""'
    end
    if not s:find(" \t\"", 1, true) then
        return s
    end
    if not s:find("\"\\", 1, true) then
        return '"'..s..'"'
    end
    local quote_hit = true
    local t = {}
    t[#t+1] = '"'
    for i = #s, 1, -1 do
        local c = s:sub(i, i)
        t[#t+1] = c
        if quote_hit and c == "\\" then
            t[#t+1] = "\\"
        elseif c == '"' then
            quote_hit = true
            t[#t+1] = "\\"
        else
            quote_hit = false
        end
    end
    t[#t+1] = '"'
    for i = 1, #t // 2 do
        local tmp = t[i]
        t[i] = t[#t - i + 1]
        t[#t - i + 1] = tmp
    end
    return table.concat(t)
end
