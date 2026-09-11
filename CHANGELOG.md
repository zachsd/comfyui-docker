# Changelog

## [0.35.1](https://github.com/zachsd/comfyui-docker/compare/v0.35.0...v0.35.1) (2026-09-11)

### Fixes

* **manager:** support ComfyUI-Manager v4+ (pip package, not custom_nodes clone). v4
  ships as the `comfyui-manager` pip package with no top-level `__init__.py`, so the
  previous "clone into `/custom_nodes` if `__init__.py` missing" check always saw v4 as
  corrupted and silently reset it back to the pre-v4 3.x git branch on every container
  restart. `svc-comfyui` now runs `pip install -U --pre comfyui-manager` instead, and
  removes any leftover legacy git-clone found under `/custom_nodes`.
* **manager:** add the missing `--enable-manager` flag to the ComfyUI launch command —
  Manager's UI/API never actually activated without it.
* **custom-nodes:** protect the pinned `torch`/`torchvision`/`torchaudio` build (and
  `pip`/`setuptools`/`wheel`) from being shadowed by a custom node's `requirements.txt`,
  directly or via a transitive dependency such as `transformers`/`accelerate`, using a
  pip constraints file. An unpinned `torch` line previously broke SageAttention with
  `undefined symbol: ...materialize_cow_storage...` after installing an unrelated custom
  node.
* **custom-nodes:** normalize CRLF line endings before filtering protected packages — a
  stray `\r` broke the filter's end-of-line anchor and let a protected package slip
  through.
* **custom-nodes:** retry a failed `requirements.txt` install package-by-package instead
  of giving up on the whole file — `pip install -r` fails atomically on a single
  unavailable line (e.g. `decord`, no Linux aarch64 wheel), which was blocking every
  other, perfectly-installable dependency declared in the same file.

## 0.35.0 (2026-09-10)

Initial release. ComfyUI v0.35.0 + SageAttention v2.2.0, packaged with LinuxServer.io-style
conventions and a bundled comfy-mcp server, for NVIDIA DGX Spark (GB10/sm_121/ARM64).
