local setmetatable = setmetatable

local monotonic = require 'bee.time'.monotonic

local m = {}

local single_what
local single_time
local perf_closeable = setmetatable({}, {__close = function()
    local time = monotonic() - single_time
    print(("%s: %dms."):format(single_what, time))
end})

function m.single(what)
    single_what = what
    single_time = monotonic()
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
            local time = monotonic() - status[what]
            status[what] = nil
            totals[what] = totals[what] + time
        end})
        closeables[what] = closeable
    end
    status[what] = monotonic()
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
        print(("%s: %dms."):format(k, totals[k]))
    end
end

return m
