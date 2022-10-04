#!/usr/bin/env sh

case "`uname`" in
  MSYS_NT*|MINGW64_NT*|Windows_NT*)
    OS=mingw
    ;;
  Linux)
    case "`uname -o`" in
      Android)
        OS=android
        ;;
      *)
        OS=linux
        ;;
    esac
    ;;
  Darwin)
    OS=macos
    ;;
  NetBSD)
    OS=netbsd
    ;;
  FreeBSD)
    OS=freebsd
    ;;
  OpenBSD)
    OS=openbsd
    ;;
  *)
    echo "Unknown OS" "`uname`"
    exit 1
    ;;
esac

DIR=$(cd `dirname $0`/..; pwd)
exec ninja -f $DIR/compile/ninja/$OS.ninja $*
