local action = require "action"

action.init()
local code = action.execute {
    stdout = io.stdout,
    table.unpack(arg, 2)
}
if code ~= 0 then
    os.exit(code)
end
