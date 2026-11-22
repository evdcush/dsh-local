# DeepSeek Harness (dsh) — single-user, local-only Web UI.
#
# Node >= 24.9 is required by @deepseek-ai/dsh. All native dependencies
# (node-pty, koffi, ...) ship platform prebuilds, so no toolchain is needed;
# their install scripts are allowed below so the prebuilt binaries land.

FROM node:24-bookworm-slim

ARG DSH_VERSION=0.2.2-rc.5

ENV DEBIAN_FRONTEND=noninteractive \
    npm_config_update_notifier=false \
    npm_config_fund=false \
    npm_config_audit=false \
    DSH_HOME=/data/dsh \
    DSH_AGENTS_HOME=/data/agents

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    # default deb archive has turd speeds; i pick mirror near me via apt-select
    && sed -Ei \
      's|^URIs: https?://deb\.debian\.org/debian$|URIs: https://ftp.tsukuba.wide.ad.jp/debian|' \
      /etc/apt/sources.list.d/debian.sources \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get update && apt-get install -y --no-install-recommends \
      autoconf \
      automake \
      bash \
      bison \
      build-essential \
      ca-certificates \
      ccache \
      clang \
      cmake \
      curl \
      fd-find \
      file \
      flex \
      gdb \
      git \
      git-lfs \
      glslc \
      glslang-tools \
      jq \
      less \
      libcurl4-openssl-dev \
      libnuma-dev \
      libomp-dev \
      libopenblas-dev \
      libssl-dev \
      libtool \
      libvulkan-dev \
      lld \
      llvm \
      make \
      nano \
      ninja-build \
      ocl-icd-opencl-dev \
      openssh-client \
      pkg-config \
      procps \
      python3 \
      python3-pip \
      python3-venv \
      ripgrep \
      rsync \
      shellcheck \
      sqlite3 \
      spirv-tools \
      tree \
      unzip \
      vim \
      wget \
      zip \
      zlib1g-dev \
      && ln -s /usr/bin/fdfind /usr/local/bin/fd \
      ;

RUN npm install -g --no-audit --no-fund \
      --allow-scripts="@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs" \
      "@deepseek-ai/dsh@${DSH_VERSION}" \
    && npm install -g --no-audit --no-fund \
      pnpm \
      pyright \
      typescript \
      typescript-language-server \
    && npm cache clean --force \
    && mkdir -p /data/dsh /data/agents /workspace \
    && chown -R node:node /data /workspace

# Launcher and the web profile definition seeded into $DSH_HOME on first start.
COPY --chown=node:node entrypoint.sh /opt/dsh/entrypoint.sh
COPY --chown=node:node profile/ /opt/dsh/profile/

RUN chmod +x /opt/dsh/entrypoint.sh

ENV HOME=/home/node \
    SHELL=/bin/bash \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /workspace
USER node

ENTRYPOINT ["/opt/dsh/entrypoint.sh"]
