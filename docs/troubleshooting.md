# Troubleshooting

## SageAttention: `ValueError: Unsupported CUDA architecture: smXXX`

You're not on this image's GB10-patched build, or you rebuilt it without the
dispatch patch — see `docs/building.md`, "SageAttention on GB10". This image
ships the fix already; if you hit this, check `ENABLE_SAGE_ATTENTION` is
`true` and confirm you're actually running `ghcr.io/zachsd/comfyui-docker`,
not a stock ComfyUI + pip-installed SageAttention image.

## Images render solid black (SDXL or similar)

Almost always a `--force-fp16`/`--fp16-vae`/`--dont-upcast-attention`
combination — this is a known SDXL VAE-NaN-in-pure-fp16 issue, unrelated to
SageAttention. This image's default launch flags don't include them. If
you've added `COMFYUI_EXTRA_ARGS` with any of those, remove them.

## "Missing models" popup in a workflow, but no download button / empty search

ComfyUI-Manager's model database is crowd-sourced and lags new or renamed
model releases (this happened with LTX-2.5 vs LTX-2 filenames). Check the
node's expected filename on the actual model's Hugging Face/CivitAI page and
pull it directly:

```bash
docker exec -it comfyui pull-model hf <repo_id> <file...>
```

See [docs/models.md](models.md) for the full walkthrough.

## GPU not visible inside the container

- Confirm `--gpus all` (docker run) / `runtime: nvidia` (compose) /
  `nvidia.com/gpu` resource request (k8s) is actually set.
- Confirm the NVIDIA Container Toolkit is installed on the host:
  `docker run --rm --gpus all nvidia/cuda:13.0.2-base-ubuntu24.04 nvidia-smi`
  should work independent of this image.
- Check `docker logs <container>` for the `[svc-comfyui] Torch:` line at
  startup — if torch loaded but reports no CUDA device, it's a host/runtime
  issue, not this image.

## comfy-mcp / port 8189 not responding

- Confirm `COMFY_MCP_ENABLED=true` (default).
- Check `docker logs <container> 2>&1 | grep svc-comfy-mcp` — it waits up
  to 2 minutes for ComfyUI itself to come up on `COMFYUI_PORT` before
  starting; if ComfyUI is crash-looping, comfy-mcp will too (by design — it
  has nothing to proxy to otherwise).
- The endpoint is `http://<host>:8189/mcp` for streamable HTTP clients, or
  `http://<host>:8189/sse` for SSE-only clients. A bare `curl` to `/mcp`
  will hang (it's a long-lived stream) — that's expected, not a bug; use
  `curl http://<host>:8189/status` for a quick health check instead.

## Permission errors on /config, /models, etc.

The volumes are chowned to `PUID:PGID` on container start
(`init-adduser`/`init-config`). If you changed `PUID`/`PGID` after the
volumes already had files owned by the old values, either:

- Let the container do it: it re-chowns on every start, so this should
  self-heal on restart, or
- Fix it manually from the host: `sudo chown -R <PUID>:<PGID> ./config ./models ...`

## Rebuilding after a Dockerfile change

Remember: **this image must be built on aarch64/ARM64 hardware** (DGX Spark
or similar) — see `docs/building.md`. A build on an x86_64 dev machine via
QEMU emulation will "work" but produce a much slower and potentially
miscompiled image; don't publish a release built that way.
