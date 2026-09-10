# Pulling models manually

ComfyUI-Manager's crowd-sourced model list lags new/renamed model releases —
it's common to open a workflow and see "missing model" with no download
button because Manager's database just doesn't know that file yet. This image
bundles a `pull-model` script so you can fetch a model directly from
Hugging Face or CivitAI, straight into the correct `/models` subfolder,
without waiting on Manager's database to catch up.

Set up your tokens first — see [authentication.md](authentication.md) —
`pull-model` works without one but gated repos/models will fail.

## Usage

Run it inside the running container:

```bash
docker exec -it comfyui pull-model hf <repo_id> <file_in_repo> [<file_in_repo> ...] [--dest <subfolder>]
docker exec -it comfyui pull-model civitai <model-version-id> [--dest <subfolder>] [--force]
```

(`comfyui` above is the container name — adjust if yours differs, or use
`kubectl exec -it deploy/comfyui -- pull-model ...` on Kubernetes.)

### Hugging Face

```bash
docker exec -it comfyui pull-model hf Lightricks/LTX-2.5 \
  vae/ltx-2.5-video-vae-bf16.safetensors \
  vae/ltx-2.5-audio-vae-bf16.safetensors
```

- `repo_id` is the Hugging Face repo, e.g. `Lightricks/LTX-2.5`.
- Each `file_in_repo` is the **repo-relative path**, exactly as shown on the
  repo's "Files" tab on huggingface.co. The leading folder
  (`text_encoders/`, `diffusion_models/`, `vae/`, `loras/`, ...) should match
  a ComfyUI `/models` subfolder — most ComfyUI-targeted HF repos already use
  ComfyUI's own folder names, so files land in the right place automatically.
- You can pass multiple files in one call; they download in sequence.

This is a thin wrapper around `hf download ... --local-dir /models`, so it
gets resumable downloads and correct LFS handling for free.

**When the repo's own layout doesn't match ComfyUI's folders** — plenty of
HF repos aren't ComfyUI-targeted and just dump files at repo root or under
their own naming — pass `--dest` to force everything into one `/models`
subfolder, flattening the repo-relative path:

```bash
docker exec -it comfyui pull-model hf Comfy-Org/stable-diffusion-v1-5-archive \
  v1-5-pruned-emaonly-fp16.safetensors --dest checkpoints
```

That lands the file at `/models/checkpoints/v1-5-pruned-emaonly-fp16.safetensors`
regardless of where it lived in the source repo.

### CivitAI

```bash
docker exec -it comfyui pull-model civitai 2514310
```

- The argument is the **model VERSION id**, not the model id. Find it on the
  model's CivitAI page — it's the number in the download URL
  (`civitai.com/api/download/models/<this number>`) or in the version
  dropdown's URL.
- The destination subfolder is auto-detected from CivitAI's own `type` field
  (`Checkpoint` → `checkpoints`, `LORA` → `loras`, `VAE` → `vae`, etc). Override
  with `--dest <subfolder>` if you need something different.
- `--force` re-downloads even if a file with that name already exists.
- Progress prints to stderr as the download runs.

## Where files land

Both subcommands write into `/models/<subfolder>/<filename>`, which is the
same volume ComfyUI itself reads from — no restart needed, just hit "Refresh"
in the ComfyUI-Manager UI or reload the page so the new file shows up in node
dropdowns.

**Ownership note:** `docker exec` runs as root by default, not the
PUID/PGID-mapped `comfy` user, so files downloaded this way land owned by
root on the host. That's harmless for ComfyUI itself (it doesn't care about
file ownership, only read access), but if you want the file owned by your
mapped user for host-side tooling, either run `docker exec -u comfy -it
comfyui pull-model ...` instead, or `chown` it afterward:
`docker exec comfyui chown ${PUID}:${PGID} /models/checkpoints/<file>`.

## Automating pulls at startup

`pull-model` is meant for ad-hoc/on-demand pulls. If you want a fixed set of
models present every time the container starts, mount a script into
`/custom_nodes` isn't the right place for that — instead, run `pull-model`
once from the host (or a CI job) against the mounted `/models` volume /
`/ai/models/...` hostPath before starting ComfyUI, or `docker exec` it after
`docker compose up -d` in your own automation. There's no first-boot
"model manifest" convention baked into this image on purpose — a shell
script explicitly calling `pull-model` is easier to read and debug than a
YAML manifest format we'd have to also document and maintain.
