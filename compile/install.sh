#!/usr/bin/env bash

case "`uname`" in
  MSYS_NT*)
    ninja -f ninja/mingw.ninja
    ;;
  Linux)
    ninja -f ninja/linux.ninja
    ;;
  Darwin)
    ninja -f ninja/macos.ninja
    ;;
  *)
    echo "Unknown OS $OS"
    exit 1
    ;;
esac

write_profile()
{
    work_path=$(pwd)
    grep -sq "luamake" $1 || echo -e "\nalias luamake=$work_path/luamake" >> $1
}

if   [[ "$SHELL" = */zsh ]]; then
    write_profile ~/.zshrc
elif [[ "$SHELL" = */ksh ]]; then
    write_profile ~/.kshrc
elif [[ "$SHELL" = */bash ]]; then
    write_profile ~/.bashrc
    if [ "$(uname)" == "Darwin" ]; then
        write_profile ~/.bash_profile
    fi
else write_profile ~/.profile 
fi
