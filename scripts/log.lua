local m = {}

local traceback; do
    local procdir = "@"..package.procdir.."/scripts"
    local function in_procdir(path)
        if path:sub(1, #procdir) == procdir then
            return true
        end
    end
    local function getshortsrc(source)
        local maxlen <const> = 60
        local type = source:byte(1)
        if type == 61 --[['=']] then
            if #source <= maxlen then
                return source:sub(2)
            else
                return source:sub(2, maxlen)
            end
        elseif type == 64 --[['@']] then
            if #source <= maxlen then
                return source:sub(2)
            else
                return "..."..source:sub(#source - maxlen + 5)
            end
        else
            local nl = source:find "\n"
            local string_maxlen <const> = maxlen - 15
            if #source < string_maxlen and nl == nil then
                return ('[string "%s"]'):format(source)
            else
                local n = #source
                if nl ~= nil then
                    n = nl - 1
                end
                if n > string_maxlen then
                    n = string_maxlen
                end
                return ('[string "%s..."]'):format(source:sub(1, n))
            end
        end
    end
    local function findfield(t, f, level)
        if level == 0 or type(t) ~= "table" then
            return
        end
        for key, value in pairs(t) do
            if type(key) == "string" and not (level == 2 and key == "_G") then
                if value == f then
                    return key
                end
                local res = findfield(value, f, level - 1)
                if res then
                    return key.."."..res
                end
            end
        end
    end
    local function pushglobalfuncname(f)
        return findfield(_G, f, 2)
    end
    local function pushfuncname(info)
        local funcname = pushglobalfuncname(info.func)
        if funcname then
            return ("function '%s'"):format(funcname)
        elseif info.namewhat ~= "" then
            return ("%s '%s'"):format(info.namewhat, info.name)
        elseif info.what == "main" then
            return "main chunk"
        elseif info.what ~= "C" then
            return ("function <%s:%d>"):format(getshortsrc(info.source), info.linedefined)
        else
            return "?"
        end
    end
    function traceback(level, errmsg)
        local s = {
            errmsg,
            "\nstack traceback:\n"
        }
        local depth = level or 0
        while true do
            local info = debug.getinfo(depth, "Slntf")
            if not info then
                break
            end
            if info.source:byte(1) == 61 --[['=']] then
                goto continue
            end
            if in_procdir(info.source) then
                goto continue
            end
            s[#s+1] = ("\t%s:"):format(getshortsrc(info.source))
            if info.currentline > 0 then
                s[#s+1] = ("%d:"):format(info.currentline)
            end
            s[#s+1] = " in "
            s[#s+1] = pushfuncname(info)
            if info.istailcall then
                s[#s+1] = "\n\t(...tail calls...)"
            end
            s[#s+1] = "\n"
            ::continue::
            depth = depth + 1
        end
        if #s == 2 then
            s[3] = "\tNo stack traceback available."
        end
        return table.concat(s)
    end
end

local protected = false

local function fatal(errmsg)
    errmsg = traceback(3, errmsg)
    if protected then
        error { __luamake = errmsg }
    else
        io.stderr:write(errmsg)
        os.exit(false)
    end
end

function m.assert(cond, fmt, ...)
    if not cond then
        fatal(fmt:format(...))
    end
    return cond
end

function m.fatal(fmt, ...)
    fatal(fmt:format(...))
end

function m.fastfail(fmt, ...)
    io.stderr:write("Failed: " .. fmt:format(...))
    os.exit(false)
end

local function conv_error(err)
    if type(err) == "table" and err.__luamake then
        return err.__luamake
    end
    return err
end

function m.pcall(f, ...)
    protected = true
    local r = table.pack(pcall(f, ...))
    protected = false
    if r[1] then
        return table.unpack(r, 1, r.n)
    end
    local err = r[2]
    return nil, conv_error(err)
end

function m.xpcall(f, msgh, ...)
    local function error_handler(err)
        return msgh(conv_error(err))
    end
    protected = true
    local r = table.pack(xpcall(f, error_handler, ...))
    protected = false
    return table.unpack(r, 1, r.n)
end

return m
