@ECHO OFF
CALL compile\msvc\find_msvc.bat
call compile\msvc\generate_msvc_deps_prefix.bat
@ECHO ON

ninja -f build\msvc\compile.ninja

@ECHO OFF
call compile\msvc\setpath.bat
@ECHO ON
