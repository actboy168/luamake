os.execute "mkdir temp 2>nul"
os.execute "type nul>temp/test.h"
os.execute "echo #include \"test.h\" >temp/test.c"

local stdout = io.popen("cd temp && cl /showIncludes /nologo test.c")
local prefix
for line in stdout:lines() do
    local m = line:match('[^:]+:[^:]+:')
    if m then
        prefix = m
        break
    end
end
stdout:close()
os.execute "rmdir /q /s temp"
assert(prefix, "can't find msvc.")

os.execute [[mkdir ..\..\3rd\bee.lua\build\msvc 2>nul]]
os.execute(([[cd ..\..\3rd\bee.lua\build\msvc && (echo builddir = build/msvc&&echo msvc_deps_prefix = %s&&echo subninja ninja/msvc.ninja) >msvc-init.ninja]]):format(prefix))
