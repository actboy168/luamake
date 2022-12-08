@ECHO OFF
CALL compile\msvc\find_msvc.bat
CALL compile\msvc\generate_msvc_deps_prefix.bat
@ECHO ON

ninja -f build\msvc\compile.ninja %*
