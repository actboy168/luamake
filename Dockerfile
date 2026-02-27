ARG GIT_REF=master

FROM ubuntu:latest

RUN apt-get update && apt-get install -y \
    git ninja-build gcc g++ linux-headers-generic

WORKDIR /luamake
RUN git clone --depth 1 --branch "${GIT_REF}" https://github.com/actboy168/luamake.git .
RUN git submodule update --init

RUN ninja -f "compile/ninja/linux.ninja"

ENTRYPOINT ["/luamake/luamake"]
