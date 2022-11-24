#!/usr/bin/env sh

sh ./compile/build.sh

if [ "$?" != "0" ]
then
  exit 1
fi

DIR=$(cd `dirname $0`/..; pwd)

write_v1()
{
    grep -sq "luamake" $1 || echo -e "\nalias luamake=$DIR/luamake" >> $1
}

write_v2()
{
    grep -sq "luamake" $1 || echo -e "\nalias luamake $DIR/luamake" >> $1
}

write_v3()
{
    grep -sq "luamake" $1 || echo "\nalias luamake=$DIR/luamake" >> $1
}

include () {
    [ -f "$1" ] && source "$1"
}

case "$SHELL" in
  */zsh)
    include ~/.zshenv
    if [ -d "$ZDOTDIR" ]; then
        write_v1 "$ZDOTDIR"/.zshrc
    else
        write_v1 ~/.zshrc
    fi
    ;;
  */ksh)
    if [ "$(uname)" == "OpenBSD" ]; then
        write_v1 ~/.profile
    else
        write_v1 ~/.kshrc
    fi
    ;;
  */csh)
    write_v2 ~/.cshrc
    ;;
  */bash)
    if [ "$BASH_VERSION" != '' ]; then
        write_v1 ~/.bashrc
        if [ "$(uname)" == "Darwin" ]; then
            write_v1 ~/.bash_profile
        fi
    else
        write_v3 ~/.bashrc
    fi
    ;;
  *)
    write_v1 ~/.profile
    ;;
esac
