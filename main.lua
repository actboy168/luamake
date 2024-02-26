package.procdir = package.cpath:match("(.+)[/][^/]+$")
package.path = package.procdir.."/scripts/?.lua"
require "main"
