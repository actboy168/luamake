FROM ubuntu:latest AS builder

ARG GIT_REF=master

RUN apt-get update && apt-get install -y \
    git ninja-build gcc g++ linux-headers-generic

WORKDIR /luamake
RUN set -eu; \
    git check-ref-format --branch "${GIT_REF}"; \
    git clone --depth 1 --branch "${GIT_REF}" -- https://github.com/actboy168/luamake.git .
RUN git submodule update --init

RUN ninja -f "compile/ninja/linux.ninja"

# Clean up files that are not needed at runtime (.github, .vscode, etc.)
RUN rm -rf /luamake/.[!.]* /luamake/compile /luamake/doc /luamake/build

FROM ubuntu:latest

RUN apt-get update && apt-get install -y \
    ninja-build && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /luamake /luamake

ENTRYPOINT ["/luamake/luamake"]
