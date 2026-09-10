# syntax=docker/dockerfile:1.7
#
# comfyui-docker — ComfyUI + SageAttention, tuned for NVIDIA DGX Spark (GB10 /
# sm_121 / aarch64), packaged with LinuxServer.io-style container conventions
# (s6-overlay init, PUID/PGID/TZ, /config+/models+/input+/output volumes) and
# a bundled comfy-mcp server on a second port.
#
# MUST be built natively on aarch64 (DGX Spark or equivalent) — the PyTorch
# and SageAttention wheels/kernels below are architecture- and
# compute-capability-specific; cross-arch/QEMU builds are far slower and can
# silently miscompile CUDA kernels. See docs/building.md.

ARG BASE_IMAGE=nvidia/cuda:13.0.2-devel-ubuntu24.04
FROM ${BASE_IMAGE} AS base

LABEL org.opencontainers.image.title="comfyui-docker" \
      org.opencontainers.image.description="ComfyUI + SageAttention for NVIDIA DGX Spark (GB10/sm_121/aarch64), with bundled MCP server" \
      org.opencontainers.image.source="https://github.com/zachsd/comfyui-docker" \
      org.opencontainers.image.licenses="GPL-3.0-or-later"

ARG DEBIAN_FRONTEND=noninteractive

# ---- Pinned versions ------------------------------------------------------
# Keep these in sync with README.md's "Version matrix" table when bumping.
ARG COMFYUI_REF=v0.35.0
ARG SAGEATTN_REF=v2.2.0
ARG S6_OVERLAY_VERSION=3.2.3.2
ARG TORCH_VERSION=2.11.0
ARG TORCHVISION_VERSION=0.26.0
ARG TORCH_CUDA_INDEX=https://download.pytorch.org/whl/cu130

# ---- System packages -------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl xz-utils tzdata gosu \
        git git-lfs \
        python3 python3-pip python3-venv python3-dev \
        build-essential ninja-build cmake pkg-config \
        libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# ---- s6-overlay (process supervisor / init system) -------------------------
# Standard LinuxServer.io-style init: PID 1 is s6, services + one-shot init
# scripts are declared as s6-rc units under /etc/s6-overlay/s6-rc.d/.
ARG TARGETARCH
RUN set -eux; \
    case "${TARGETARCH:-arm64}" in \
        amd64)  S6_ARCH=x86_64 ;; \
        arm64)  S6_ARCH=aarch64 ;; \
        *) echo "unsupported TARGETARCH: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/s6-overlay-noarch.tar.xz \
        "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz"; \
    curl -fsSL -o "/tmp/s6-overlay-${S6_ARCH}.tar.xz" \
        "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz"; \
    tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz; \
    tar -C / -Jxpf "/tmp/s6-overlay-${S6_ARCH}.tar.xz"; \
    rm -f /tmp/s6-overlay-*.tar.xz

ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
    S6_VERBOSITY=1

# ---- Python venv ------------------------------------------------------------
ENV VENV=/opt/venv
RUN python3 -m venv $VENV
ENV PATH="$VENV/bin:$PATH"
RUN pip install -U pip setuptools wheel

# ---- PyTorch (ARM64 + CUDA 13.0) --------------------------------------------
# Pinned, not "latest": SageAttention 2.2.0's C++ source calls the internal
# API at::symint::sizes<T>(), removed/renamed in torch >= 2.13. Bump only
# after confirming a newer torch still builds SageAttention cleanly (see
# docs/building.md, "Bumping PyTorch").
RUN pip install --index-url ${TORCH_CUDA_INDEX} \
    torch==${TORCH_VERSION}+cu130 torchvision==${TORCHVISION_VERSION}+cu130

# ---- ComfyUI -----------------------------------------------------------------
ENV COMFYUI_PATH=/opt/ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git ${COMFYUI_PATH} && \
    cd ${COMFYUI_PATH} && git checkout ${COMFYUI_REF} && \
    git rev-parse HEAD > ${COMFYUI_PATH}/.build-commit

RUN pip install -r ${COMFYUI_PATH}/requirements.txt

# ---- SageAttention (sm_121-correct, GB10/Blackwell) --------------------------
# Three fixes were required to get a working sm_121 build; see
# docs/building.md, "SageAttention on GB10" for the full root-cause writeup.
ENV TORCH_CUDA_ARCH_LIST="12.0"
ENV CUDA_HOME=/usr/local/cuda
RUN MAX_JOBS=8 pip install --no-build-isolation \
    "git+https://github.com/thu-ml/SageAttention@${SAGEATTN_REF}"

# sageattn()'s Python dispatch (sageattention/core.py) keys off the literal
# torch.cuda.get_device_capability() string and has no "sm121" branch, even
# though the compiled sm_120 kernels run correctly on sm_121 (binary
# compatible). Route sm121 through the same fp8 codepath as sm120.
RUN SAGE_CORE="${VENV}/lib/python3.12/site-packages/sageattention/core.py" && \
    sed -i 's/elif arch == "sm120":/elif arch in ("sm120", "sm121"):/' "$SAGE_CORE" && \
    grep -q '"sm120", "sm121"' "$SAGE_CORE"

# ---- comfy-mcp (bundled MCP server) ------------------------------------------
# comfy-mcp is stdio-only; mcp-proxy wraps it as streamable-HTTP/SSE on
# COMFY_MCP_PORT so any MCP-speaking AI client can point at this one
# container. mcp-proxy gets its own isolated `uv tool` venv and a pinned
# `mcp<2.0.0` — installing it into the same site-packages as comfy-mcp (which
# needs mcp>=2.0) breaks both: mcp-proxy 0.12.0 sets no upper bound on its
# `mcp` SDK dependency, and SDK 2.0.0 removed an API mcp-proxy imports
# (ImportError: cannot import name 'request_ctx'). Revisit this pin once
# mcp-proxy ships its own upper bound.
RUN pip install --no-cache-dir "comfy-cli>=1.14.0" comfy-mcp uv toml GitPython && \
    UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/opt/uv-tools/bin \
        uv tool install --with "mcp<2.0.0" mcp-proxy
ENV PATH="/opt/uv-tools/bin:${PATH}"

# ---- Filesystem prep ----------------------------------------------------------
# Own the venv + ComfyUI install as uid/gid 1000 (this image's default
# PUID/PGID) so the non-root runtime user can write there: ComfyUI writes
# its own /temp and /input/3d scratch dirs at startup, and ComfyUI-Manager
# installs missing custom-node Python deps into the venv on first run.
# init-adduser re-chowns both trees at container start *only* when the
# operator overrides PUID/PGID away from the 1000:1000 default (see
# root/etc/s6-overlay/s6-rc.d/init-adduser/run) — avoids a slow recursive
# chown of the whole venv on every ordinary boot.
RUN mkdir -p ${COMFYUI_PATH}/temp ${COMFYUI_PATH}/input/3d && \
    chown -R 1000:1000 ${VENV} ${COMFYUI_PATH} /opt/uv-tools

RUN mkdir -p /defaults
COPY defaults/ /defaults/

# root/ mirrors the container's filesystem root: s6-rc service definitions
# and helper scripts. See root/etc/s6-overlay/s6-rc.d/ for the service graph.
COPY root/ /

# Defensive: never let volume-staged file permissions leak onto core system
# paths (this bit us once during development — a COPY from a restrictively
# permissioned build context silently made ...[truncated]

# ---- Runtime defaults (override via `docker run -e`) --------------------------
ENV PUID=1000 \
    PGID=1000 \
    UMASK=022 \
    TZ=Etc/UTC \
    COMFYUI_PORT=8188 \
    COMFYUI_EXTRA_ARGS="" \
    ENABLE_SAGE_ATTENTION=true \
    COMFY_MCP_ENABLED=true \
    COMFY_MCP_PORT=8189 \
    HF_TOKEN_FILE=/run/secrets/huggingface_token \
    CIVITAI_TOKEN_FILE=/run/secrets/civitai_token

VOLUME ["/config", "/models", "/input", "/output", "/custom_nodes"]
EXPOSE 8188 8189

ENTRYPOINT ["/init"]
