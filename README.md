<div align="center">

# comfyui-docker

**ComfyUI + SageAttention for NVIDIA DGX Spark (GB10 / sm_121 / ARM64), packaged with
[LinuxServer.io](https://www.linuxserver.io/)-style container conventions and a bundled
[comfy-mcp](https://github.com/Comfy-Org/comfy-mcp) server.**

[![GHCR](https://img.shields.io/badge/ghcr.io-zachsd%2Fcomfyui--docker-blue?logo=github)](https://github.com/zachsd/comfyui-docker/pkgs/container/comfyui-docker)
[![Docker Hub](https://img.shields.io/badge/docker.io-zachsd%2Fcomfyui--docker-2496ED?logo=docker)](https://hub.docker.com/r/zachsd/comfyui-docker)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

</div>

## What this is

A single container that runs:

- **[ComfyUI](https://github.com/comfyanonymous/ComfyUI)**, built with a working
  **SageAttention** for NVIDIA's DGX Spark (GB10, compute capability sm_121, ARM64) —
  getting that combination to actually work took real debugging; see
  [docs/building.md](docs/building.md) for the full root-cause writeup if you're curious
  or want to build for a different Blackwell chip.
- **[comfy-mcp](https://github.com/Comfy-Org/comfy-mcp)**, the official Comfy-Org MCP
  server, bundled and exposed on its own port — point any MCP-speaking AI client (Claude
  Code, Claude Desktop, Cursor, etc.) at this one container for all of its ComfyUI needs,
  no separate install.

Packaged using the same conventions as
[LinuxServer.io](https://docs.linuxserver.io/general/container-customization/) images:
`s6-overlay` init, `PUID`/`PGID`/`TZ` environment variables, a `/config` volume, sane
defaults out of the box.

**Who this is for:** primarily DGX Spark / GB10 owners. The image only publishes an
`arm64` build (see [docs/building.md](docs/building.md) for why cross-compiling isn't
viable here) — it will not run on x86_64 hosts.

## Quick start

```bash
docker run -d \
  --name comfyui \
  --gpus all \
  -e PUID=1000 -e PGID=1000 -e TZ=Etc/UTC \
  -p 8188:8188 \
  -p 8189:8189 \
  -v $(pwd)/config:/config \
  -v $(pwd)/models:/models \
  -v $(pwd)/input:/input \
  -v $(pwd)/output:/output \
  -v $(pwd)/custom_nodes:/custom_nodes \
  ghcr.io/zachsd/comfyui-docker:latest
```

Or with Compose — see [docker-compose.yml](docker-compose.yml) (also shows the optional
Hugging Face / CivitAI token secrets):

```bash
docker compose up -d
```

Then:
- ComfyUI web UI: `http://<host>:8188`
- comfy-mcp (for your AI agent): `http://<host>:8189/mcp` (streamable HTTP) or
  `http://<host>:8189/sse` (SSE)

Kubernetes users: see [docs/kubernetes.md](docs/kubernetes.md).

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `PUID` | `1000` | User ID the container runs as (matches the owning UID of your mounted volumes) |
| `PGID` | `1000` | Group ID, same idea as `PUID` |
| `UMASK` | `022` | Umask applied to files/dirs the container creates |
| `TZ` | `Etc/UTC` | Timezone, e.g. `America/Denver` — see the [TZ database list](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) |
| `COMFYUI_PORT` | `8188` | Port ComfyUI's web UI/API listens on inside the container |
| `COMFYUI_EXTRA_ARGS` | *(empty)* | Extra flags appended verbatim to `python main.py`, e.g. `--lowvram` |
| `ENABLE_SAGE_ATTENTION` | `true` | Pass `--use-sage-attention` to ComfyUI. Set `false` to fall back to PyTorch SDPA |
| `COMFY_MCP_ENABLED` | `true` | Run the bundled comfy-mcp server. Set `false` to disable it entirely |
| `COMFY_MCP_PORT` | `8189` | Port the bundled comfy-mcp (streamable HTTP + SSE) listens on |
| `HF_TOKEN_FILE` | `/run/secrets/huggingface_token` | Path to a mounted file containing a Hugging Face token (see [docs/authentication.md](docs/authentication.md)) |
| `HF_TOKEN` | *(unset)* | Hugging Face token as a direct value, if you're not using a mounted file |
| `CIVITAI_TOKEN_FILE` | `/run/secrets/civitai_token` | Path to a mounted file containing a CivitAI API token |
| `CIVITAI_API_TOKEN` | *(unset)* | CivitAI token as a direct value |

## Volumes

| Path | Purpose |
|---|---|
| `/config` | ComfyUI's user directory: settings, saved workflows, ComfyUI-Manager's DB cache |
| `/models` | All model weights, organized into ComfyUI's standard subfolders (`checkpoints/`, `loras/`, `vae/`, `diffusion_models/`, `text_encoders/`, ...) |
| `/input` | Input images/video for img2img, controlnet references, etc. |
| `/output` | Generated output |
| `/custom_nodes` | Custom node installs (including ComfyUI-Manager itself, auto-installed here on first boot) |

## Pulling a model manually

When a workflow needs a model ComfyUI-Manager's database doesn't know about yet (common
right after a new model release), pull it directly:

```bash
docker exec -it comfyui pull-model hf Lightricks/LTX-2.5 vae/ltx-2.5-video-vae-bf16.safetensors
docker exec -it comfyui pull-model civitai 2514310
```

Full usage, examples, and how folder auto-detection works: [docs/models.md](docs/models.md).

## Documentation

- [docs/authentication.md](docs/authentication.md) — Hugging Face / CivitAI token setup
- [docs/models.md](docs/models.md) — pulling models manually with `pull-model`
- [docs/kubernetes.md](docs/kubernetes.md) — a full k8s manifest + notes
- [docs/building.md](docs/building.md) — building from source, version pins and why, publishing a release
- [docs/troubleshooting.md](docs/troubleshooting.md) — common issues and fixes

## Credits

- [ComfyUI](https://github.com/comfyanonymous/ComfyUI) by comfyanonymous
- [SageAttention](https://github.com/thu-ml/SageAttention) by thu-ml
- [comfy-mcp](https://github.com/Comfy-Org/comfy-mcp) and
  [comfy-cli](https://github.com/Comfy-Org/comfy-cli) by Comfy-Org
- [mcp-proxy](https://github.com/sparfenyuk/mcp-proxy) by sparfenyuk
- [s6-overlay](https://github.com/just-containers/s6-overlay) by just-containers
- Container conventions (`PUID`/`PGID`/`TZ`, `/config`, s6 init layout) modeled on
  [LinuxServer.io](https://www.linuxserver.io/)'s images
- [ecarmen16/SparkyUI](https://github.com/ecarmen16/SparkyUI/) — first reference for the
  SageAttention sm_121 build pattern on DGX Spark

## License

[GPL-3.0-or-later](LICENSE), matching ComfyUI's own license. See
[NOTICE](NOTICE) for third-party license notes (SageAttention, comfy-mcp/comfy-cli are
separately licensed and not redistributed as source in this repo — the Dockerfile builds
them from their own upstream sources at image-build time).
