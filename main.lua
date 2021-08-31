do
    local sep = package.config:sub(1,1)
    local pattern = "["..sep.."][^"..sep.."]+"
    package.procdir = package.cpath:match("(.+)"..pattern.."$")
    package.path = package.procdir..sep.."scripts"..sep.."?.lua"
end

require 'main'
