# luamake

## Test

windows
```
cd test
..\luamake.exe
build\bin\lua.exe -e "package.path=[[lpeglabel\?.lua]]" lpeglabel\test.lua
```

macOS / linux

1. install ninja
2. compile bee.lua
3. rename bee to luamake

```
cd test
luamake
cd build/bin
./lua -e "package.path=[[../../lpeglabel/?.lua]]" ../../lpeglabel/test.lua
```
