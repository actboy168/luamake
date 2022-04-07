local fs = require "bee.filesystem"
local fsutil = require "fsutil"
local globals = require "globals"

local isWindows <const> = globals.hostos == "windows"
local PathSpilt <const> = isWindows and '[^/\\]*' or '[^/]*'

local MATCH_SUCCESS <const> = 0
local MATCH_PENDING <const> = 1
local MATCH_FAILED <const> = 2
local MATCH_SKIP <const> = 3

local GlobStar <const> = 0

local function pattern_copy(t, s)
    local r = {ignore=t.ignore}
    for i = s, #t do
        r[i-s+1] = t[i]
    end
    return r
end

local function compile(pattern)
    return ("^%s$"):format(pattern
        :gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0")
        :gsub("%*", PathSpilt)
    )
end

local function pattern_compile(res, root, str)
    -- compatible
    local PathSeq <const> = isWindows and '/\\' or '/'
    str = str:gsub("(%*%*)([^"..PathSeq.."])", "**/*%1")

    local ignore
    if str:sub(1,1) == "!" then
        ignore = true
        str = str:sub(2)
    end
    local pattern = {ignore=ignore}
    local path = fsutil.join(root, str)
    path:gsub(PathSpilt, function (w)
        if #w == 0 and #pattern ~= 0 then
        elseif w == '..' and #pattern ~= 0 and pattern[#pattern] ~= '..' then
            if pattern[#pattern] == GlobStar then
                error "`**/..` is not a valid glob."
            end
            pattern[#pattern] = nil
        elseif w ~= '.' then
            if w == "**" then
                pattern[#pattern+1] = GlobStar
            else
                pattern[#pattern+1] = w
            end
        end
    end)
    res[#res+1] = pattern
end

local function pattern_sub(res, pattern)
    if pattern[1] == GlobStar then
        res[#res+1] = pattern_copy(pattern, 1)
        res[#res+1] = pattern_copy(pattern, 2)
    else
        res[#res+1] = pattern_copy(pattern, 2)
        if pattern[2] == GlobStar then
            res[#res+1] = pattern_copy(pattern, 3)
        end
    end
end

local function pattern_match_(pats, path)
    if #pats == 0 then
        return MATCH_FAILED
    end
    local pat = pats[1]
    if pat == GlobStar or path:match(pat) then
        return #pats == 1 and MATCH_SUCCESS or MATCH_PENDING
    end
    return MATCH_FAILED
end

local function pattern_match(pattern, path)
    local res = pattern_match_(pattern, path)
    if pattern.ignore then
        if res == MATCH_SUCCESS then
            return MATCH_FAILED
        elseif res == MATCH_FAILED then
            return MATCH_SKIP
        end
        return MATCH_PENDING
    else
        if res == MATCH_SUCCESS then
            return MATCH_SUCCESS
        elseif res == MATCH_FAILED then
            return MATCH_SKIP
        end
        return MATCH_PENDING
    end
end

local function match_prefix(t, s)
    for _, v in ipairs(t) do
        if v[1] ~= s or #v <= 1 then
            return false
        end
    end
    return true
end

local function glob_compile(root, patterns)
    if #patterns == 0 then
        return root, {}
    end
    local res = {}
    for _, pattern in ipairs(patterns) do
        pattern_compile(res, root, pattern)
    end
    local gcd = {}
    local first = res[1]
    while true do
        local r = first[1]
        if r == nil then
            break
        end
        if r == GlobStar then
            break
        end
        if r:match "%*" then
            break
        end
        if not match_prefix(res, r) then
            break
        end
        for _, v in ipairs(res) do
            table.remove(v, 1)
        end
        gcd[#gcd+1] = r
    end
    for _, v in ipairs(res) do
        for i, w in ipairs(v) do
            if w ~= GlobStar then
                v[i] = compile(w)
            end
        end
    end
    for i = 1, #res do
        local v = res[i]
        if v[1] == GlobStar then
            res[#res+1] = pattern_copy(v, 2)
        end
    end
    return fsutil.join(table.unpack(gcd)), res
end

local function glob_match_dir(patterns, path)
    local sub = {}
    for _, pattern in ipairs(patterns) do
        local res = pattern_match(pattern, path)
        if res == MATCH_SUCCESS then
        elseif res == MATCH_FAILED then
            return MATCH_FAILED
        elseif res == MATCH_PENDING then
            pattern_sub(sub, pattern)
        end
    end
    if #sub == 0 then
        return MATCH_FAILED
    end
    return MATCH_PENDING, sub
end

local function glob_match_file(patterns, path)
    local suc = false
    for _, pattern in ipairs(patterns) do
        local res = pattern_match(pattern, path)
        if res == MATCH_SUCCESS then
            suc = true
        elseif res == MATCH_FAILED then
            return MATCH_FAILED
        end
    end
    if suc then
        return MATCH_SUCCESS
    end
    return MATCH_FAILED
end

local function glob_match(patterns, path)
    local filename = path:filename():string()
    if fs.is_directory(path) then
        return glob_match_dir(patterns, filename)
    else
        return glob_match_file(patterns, filename)
    end
end

local function glob_scan_(patterns, dir, result)
    if #patterns == 0 then
        return
    end
    for path in fs.pairs(dir) do
        local res, sub = glob_match(patterns, path)
        if res == MATCH_PENDING then
            glob_scan_(sub, path, result)
        elseif res == MATCH_SUCCESS then
            result[#result+1] = path:string()
        end
    end
end

local function glob_scan(patterns, dir)
    local result = {}
    glob_scan_(patterns, dir, result)
    return result
end

return function (dir, patterns)
    local root, compiled = glob_compile(dir, patterns)
    return glob_scan(compiled, fs.path(root))
end
