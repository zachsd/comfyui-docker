# Building this image

This image **must be built natively on aarch64/ARM64 hardware** (a DGX Spark
or another GB10/Blackwell ARM64 box). Cross-compiling via QEMU is 10-20x
slower and has been known to silently miscompile CUDA extension kernels
(CUTLASS template issues) — not worth the risk for a GPU inference image.

```bash
git clone https://github.com/zachsd/comfyui-docker
cd comfyui-docker
docker build -t comfyui-docker:local .
```

Build args (all optional, see `Dockerfile` for current defaults):

| Arg | Default | Purpose |
|---|---|---|
| `COMFYUI_REF` | pinned tag, see Dockerfile | ComfyUI git ref to build |
| `SAGEATTN_REF` | `v2.2.0` | SageAttention git tag |
| `S6_OVERLAY_VERSION` | pinned | s6-overlay release |
| `TORCH_VERSION` / `TORCHVISION_VERSION` | pinned | PyTorch versions (see below — do not bump casually) |

```bash
docker build \
  --build-arg COMFYUI_REF=v0.36.0 \
  -t comfyui-docker:v0.36.0 .
```

## Version matrix

The release tag of this image tracks the ComfyUI release it bundles
(`COMFYUI_REF`). Keep this table and the Dockerfile's `ARG` defaults in sync
when bumping:

| Component | Pinned to | Why pinned |
|---|---|---|
| ComfyUI | see `COMFYUI_REF` in Dockerfile | image release version = this |
| PyTorch | `2.11.0+cu130` | see "Bumping PyTorch" below |
| SageAttention | `v2.2.0` tag (not `main`) | see "SageAttention on GB10" below |
| s6-overlay | pinned release | init system, bump freely |

## SageAttention on GB10 (sm_121)

Getting SageAttention to actually run — not just install — on a GB10 GPU
required three separate fixes. If you're touching the SageAttention build
steps in the Dockerfile, understand all three before changing anything:

1. **PyTorch pin.** SageAttention 2.2.0's C++ source calls the internal
   PyTorch API `at::symint::sizes<T>()`, which torch >= 2.13 removed/renamed.
   Building against a newer torch fails with
   `'sizes' is not a member of 'at::symint'`. This is why `TORCH_VERSION` is
   pinned rather than tracking PyTorch's latest release.

2. **Build architecture flag.** SageAttention's `setup.py`
   `SUPPORTED_ARCHS` only lists `"12.0"`, not `"12.1"` — even though GB10
   *is* sm_121. sm_120 and sm_121 are binary-compatible (confirmed via
   `cuobjdump --list-text` on the compiled `.so` files), so the Dockerfile
   builds with `TORCH_CUDA_ARCH_LIST="12.0"` and the resulting kernels work
   fine on real sm_121 hardware.

3. **Runtime dispatch patch.** Even with correctly-compiled sm_120 kernels
   present, `sageattention/core.py`'s `sageattn()` function reads
   `torch.cuda.get_device_capability()` (→ the literal string `"sm121"` on
   GB10) and only has dispatch branches for sm80/86/89/90/120 — so it raises
   `ValueError: Unsupported CUDA architecture: sm121` despite the matching
   kernels being present and working. The Dockerfile `sed`-patches that
   dispatch to route `sm121` through the same fp8 codepath as `sm120`. This
   has **no upstream fix as of SageAttention 2.2.0** — re-verify this patch
   (or check whether it's now unnecessary) whenever you bump `SAGEATTN_REF`.

**Skipped on purpose:** SageAttention 3 (the `main` branch head as of this
writing). Upstream issue [thu-ml/SageAttention#321](https://github.com/thu-ml/SageAttention/issues/321)
reports mosaic visual artifacts on DGX Spark; we stayed on the 2.2.0 tag to
avoid that risk.

**Do not combine SageAttention with `--force-fp16 --fp16-vae
--fp16-text-enc --dont-upcast-attention`.** Those flags (independent of
SageAttention) cause SDXL to render solid-black output — a known SDXL VAE
NaN-in-pure-fp16 issue, confirmed here via a side-by-side test with/without
those flags on an identical workflow and SageAttention build. This image
does not pass them.

## Bumping PyTorch

Before changing `TORCH_VERSION`/`TORCHVISION_VERSION`:

1. Build the image with the new version.
2. Run the smoke test in the container:
   ```python
   import torch
   from sageattention import sageattn
   q = k = v = torch.randn(1, 8, 128, 64, device="cuda", dtype=torch.float16)
   out = sageattn(q, k, v)
   torch.cuda.synchronize()
   assert not torch.isnan(out).any()
   print("OK:", out.shape, out.dtype)
   ```
   If the `pip install ... SageAttention` build step fails with an
   `at::symint` error, the new torch version broke the same internal API —
   don't bump until upstream SageAttention supports it.
3. Actually generate an image (not just run the kernel in isolation) and
   visually confirm it's coherent, not garbled — a broken attention kernel
   on this hardware has previously produced numerically "valid" (non-NaN)
   but visually corrupted output. See `docs/troubleshooting.md`.

## Bundled comfy-mcp

`comfy-mcp` (Comfy-Org's official local MCP server) is stdio-only by
design — it's meant to be launched as a subprocess by an MCP client on the
same machine. To expose it as a normal network port from this container, the
Dockerfile wraps it with [`mcp-proxy`](https://github.com/sparfenyuk/mcp-proxy),
which bridges stdio to streamable-HTTP/SSE.

`mcp-proxy` gets its own isolated `uv tool install` venv, pinned to
`mcp<2.0.0`, installed *separately* from comfy-mcp's own dependencies:
`mcp-proxy` 0.12.0 sets no upper bound on its `mcp` SDK dependency, and the
SDK's 2.0.0 release removed an API `mcp-proxy` imports
(`ImportError: cannot import name 'request_ctx' from
'mcp.server.lowlevel.server'`). Sharing one `mcp` install between the two
tools breaks whichever one needs the version the other doesn't. Revisit this
pin once `mcp-proxy` ships its own upper bound.

## Publishing a release

This repo's version is meant to track the bundled ComfyUI release
(`COMFYUI_REF`), not independent semver-from-commits — release-please can't
infer "bump to match upstream ComfyUI" on its own, so that's a manual edit:

1. Bump `COMFYUI_REF` in the `Dockerfile` to the new ComfyUI tag.
2. Update `.release-please-manifest.json` to match:
   ```json
   { ".": "0.36.0" }
   ```
3. Commit both (`chore: bump ComfyUI to v0.36.0`) and push to `main`.
   release-please opens a release PR; merging it tags the release and
   updates `CHANGELOG.md`.

Because the image must be built on real ARM64/GB10 hardware, **the
build+push itself stays manual** — release-please (`.github/workflows/release-please.yml`)
only manages the changelog/tag, it does not build or publish the image.
After the release PR merges and creates a tag:

```bash
git pull && git checkout <new-tag>
docker build -t comfyui-docker:<new-tag> -t comfyui-docker:latest .

# Push to both registries
docker tag comfyui-docker:<new-tag> ghcr.io/zachsd/comfyui-docker:<new-tag>
docker tag comfyui-docker:<new-tag> ghcr.io/zachsd/comfyui-docker:latest
docker push ghcr.io/zachsd/comfyui-docker:<new-tag>
docker push ghcr.io/zachsd/comfyui-docker:latest

docker tag comfyui-docker:<new-tag> docker.io/zachsd/comfyui-docker:<new-tag>
docker tag comfyui-docker:<new-tag> docker.io/zachsd/comfyui-docker:latest
docker push docker.io/zachsd/comfyui-docker:<new-tag>
docker push docker.io/zachsd/comfyui-docker:latest
```
