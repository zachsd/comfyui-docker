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

## "Missing node packs... install comfyui-manager" even though Manager is running

This is ComfyUI's generic missing-node-pack message — it fires for **any** node the
workflow references that isn't installed, and always suggests reinstalling Manager
regardless of whether Manager itself is fine. Confirm Manager is actually current first:

```bash
docker exec -it comfyui /opt/venv/bin/pip show comfyui-manager
```

If that shows a recent version, the real fix is installing the specific missing custom
node pack (through the Manager UI, or `git clone` into `/custom_nodes` + restart) — not
reinstalling Manager.

## A custom node's `requirements.txt` breaks SageAttention after restart

Symptom: `ImportError: .../sageattention/_fused...so: undefined symbol:
...materialize_cow_storage...` after adding a custom node, when SageAttention worked
before. A custom node's `requirements.txt` declared (or transitively pulled in via
`transformers`/`accelerate`/etc.) an unpinned `torch`, silently upgrading the venv's torch
past the exact build SageAttention's compiled `.so` was linked against.

`svc-comfyui/run` guards against this (strips `torch`/`torchvision`/`torchaudio` lines,
normalizes CRLF line endings first since a stray `\r` can break that filter, and
constrains any transitive resolution to the already-installed versions) — but a custom
node that vendors its own bundled torch, bypassing pip entirely, can still slip past all
three protections. If you hit this, check the offending node's install method before
assuming it's an image bug.

## One bad line in a custom node's `requirements.txt` blocks every other package in it

`pip install -r requirements.txt` fails **atomically** — a single unavailable package
(e.g. `decord`, which has no Linux aarch64 wheel) aborts the whole file, so none of the
node's other, perfectly-installable dependencies get in either. `svc-comfyui/run` retries
failed files package-by-package and skips only the genuinely broken line(s) — check the
container logs for `SKIPPED (unavailable): <package>` to see exactly which dependency (and
therefore which node features) didn't make it in.

## Rebuilding after a Dockerfile change

Remember: **this image must be built on aarch64/ARM64 hardware** (DGX Spark
or similar) — see `docs/building.md`. A build on an x86_64 dev machine via
QEMU emulation will "work" but produce a much slower and potentially
miscompiled image; don't publish a release built that way.
