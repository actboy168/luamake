local n = #arg
for i = 0, n do
    arg[i-2] = arg[i]
end
arg[n] = nil
arg[n-1] = nil

assert(loadfile(arg[0]))(table.unpack(arg))
