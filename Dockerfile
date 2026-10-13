FROM ubuntu:24.04 AS compiler
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ git curl ca-certificates xz-utils \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://github.com/nim-lang/nightlies/releases/download/2026-04-24-version-2-2-bfeb3146d1638b39f69007a4ae5a23e23ae4e5ef/nim-2.2.10-linux_x64.tar.xz \
    | tar xJ -C /opt
RUN curl -fsSL -o /usr/local/bin/nimby \
    https://github.com/treeform/nimby/releases/download/0.1.26/nimby-Linux-X64 \
    && chmod +x /usr/local/bin/nimby
ENV PATH=/opt/nim-2.2.10/bin:$PATH
WORKDIR /workspace/deps
COPY galcon.lock /workspace/galcon.lock
RUN nimby sync /workspace/galcon.lock
ENV GALCON_DEPS=/workspace/deps
WORKDIR /workspace/galcon
COPY galcon.lock config.nims ./
COPY src src
COPY players players
RUN nim c -d:release -d:coworld --nimcache:/tmp/galcon-cache \
    -o:/out/galcon src/galcon.nim

FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4t64 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=compiler /out/galcon /usr/local/bin/galcon
COPY LICENSE /usr/share/doc/galcon/LICENSE
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/galcon"]
