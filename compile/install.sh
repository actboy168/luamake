#!/usr/bin/env sh

DIR="$(cd "$(dirname "$0")"/.. || exit 1; pwd)"

cd "$DIR" || exit 1

if ! sh ./compile/build.sh $*
then
  exit 1
fi


write_alias() {
  if grep -sq "luamake" "$1"
  then
    echo "luamake alias already defined in $1"
  else
    printf '\nalias luamake="%s"\n' "'$DIR/luamake'" >> "$1"
    echo "luamake alias added to $1. (You may need to restart your shell.)"
  fi
}

include () {
    [ -f "$1" ] && . "$1"
}

case "$SHELL" in
  */zsh)
    include ~/.zshenv
    if [ -d "$ZDOTDIR" ]; then
        write_alias "$ZDOTDIR"/.zshrc
    else
        write_alias ~/.zshrc
    fi
    ;;
  */ksh)
    if [ "$(uname)" = "OpenBSD" ]; then
        write_alias ~/.profile
    else
        write_alias ~/.kshrc
    fi
    ;;
  */csh)
    write_alias ~/.cshrc
    ;;
  */bash)
    if [ "$BASH_VERSION" != '' ]; then
        write_alias ~/.bashrc
        if [ "$(uname)" = "Darwin" ]; then
            write_alias ~/.bash_profile
        fi
    else
        write_alias ~/.bashrc
    fi
    ;;
  *)
    write_alias ~/.profile
    ;;
esac

echo "Done."
