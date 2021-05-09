local util = require 'util'
util.command 'init'
util.ninja { "-t", "clean" }
util.command 'make'
