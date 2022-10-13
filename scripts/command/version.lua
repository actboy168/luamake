local version = require "version"
local globals = require "globals"

print(string.format("version: %s", version))
print("--------------------")
print(string.format("hostos: %s", globals.hostos))
print(string.format("hostshell: %s", globals.hostshell))
print(string.format("compiler: %s", globals.compiler))
print(string.format("os: %s", globals.os))
