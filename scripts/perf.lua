local setmetatable = setmetatable

local gettime = require 'bee.time'.counter

local m = {}

local single_what
local single_time
local perf_closeable = setmetatable({}, {__close = function()
    local time = gettime() - single_time
    print(("%s: %.0fms."):format(single_what, time))
end})

function m.single(what)
    single_what = what
    single_time = gettime()
    return perf_closeable
end

local status = {}
local totals = {}
local closeables = {}

function m.stat(what)
    if status[what] then
        return
    end
    local closeable = closeables[what]
    if not closeable then
        totals[what] = 0
        closeable = setmetatable({}, {__close = function()
            local time = gettime() - status[what]
            status[what] = nil
            totals[what] = totals[what] + time
        end})
        closeables[what] = closeable
    end
    status[what] = gettime()
    return closeable
end

function m.print()
    local sorted = {}
    for k in pairs(totals) do
        sorted[#sorted+1] = k
    end
    table.sort(sorted, function (a, b)
        return totals[a] < totals[b]
    end)
    for _, k in ipairs(sorted) do
        print(("%s: %.0fms."):format(k, totals[k]))
    end
end

return m
