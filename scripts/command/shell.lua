local action = require "action"

action.init()
action.execute {table.unpack(arg, 2)}
