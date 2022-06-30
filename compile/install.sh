#!/usr/bin/env sh
DIR=$(cd `dirname $0`/..; pwd)

case "`uname`" in
  MSYS_NT*|MINGW64_NT*|Windows_NT*)
    ninja -f $DIR/compile/ninja/mingw.ninja
    ;;
  Linux)
    case "`uname -o`" in
      Android)
        ninja -f $DIR/compile/ninja/android.ninja
        ;;
      *)
        ninja -f $DIR/compile/ninja/linux.ninja
        ;;
    esac
    ;;
  Darwin)
    ninja -f $DIR/compile/ninja/macos.ninja
    ;;
  NetBSD)
    ninja -f $DIR/compile/ninja/netbsd.ninja
    ;;
  *)
    echo "Unknown OS $OS"
    exit 1
    ;;
esac

if [ "$?" != "0" ]
then
  exit 1
fi

write_profile()
{
    grep -sq "luamake" $1 || echo -e "\nalias luamake=$DIR/luamake" >> $1
}

include () {
    [ -f "$1" ] && source "$1"
}

if   [ "$SHELL" = */zsh ]; then
    include ~/.zshenv
    if [ -d "$ZDOTDIR" ]; then
        write_profile "$ZDOTDIR"/.zshrc
    else
        write_profile ~/.zshrc
    fi
elif [ "$SHELL" = */ksh ]; then
    write_profile ~/.kshrc
elif [ "$SHELL" = */bash ]; then
    write_profile ~/.bashrc
    if [ "$(uname)" == "Darwin" ]; then
        write_profile ~/.bash_profile
    fi
else write_profile ~/.profile
fi
