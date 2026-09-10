# Authentication (Hugging Face / CivitAI)

The container can authenticate to Hugging Face and CivitAI so gated /
login-required models can be downloaded, either automatically by
ComfyUI-Manager or manually with [`pull-model`](models.md).

Both providers follow the same pattern: a **file** env var takes priority,
a **direct value** env var is the fallback.

| Provider | File env var (recommended) | Direct value env var |
|---|---|---|
| Hugging Face | `HF_TOKEN_FILE` (default: `/run/secrets/huggingface_token`) | `HF_TOKEN` |
| CivitAI | `CIVITAI_TOKEN_FILE` (default: `/run/secrets/civitai_token`) | `CIVITAI_API_TOKEN` |

**Prefer the file form.** A plain env var (`HF_TOKEN=hf_xxx`) is visible to
anyone who can run `docker inspect` on the container, in `/proc/<pid>/environ`,
and in your shell history / compose file if you're not careful. A file mount
under Docker/Compose `secrets:` or a Kubernetes `Secret` is not.

## Getting tokens

- Hugging Face: create one at <https://huggingface.co/settings/tokens>
  (read access is enough).
- CivitAI: create one at <https://civitai.com/user/account> under
  "API Keys".

## Docker Compose

The bundled [`docker-compose.yml`](../docker-compose.yml) already wires this
up via Compose's native `secrets:` support:

```bash
mkdir -p secrets
echo -n "hf_xxxxxxxxxxxx"     > secrets/hf_token.txt
echo -n "your-civitai-key"    > secrets/civitai_token.txt
chmod 600 secrets/*.txt
docker compose up -d
```

Compose mounts each file at `/run/secrets/<name>` inside the container,
matching the `HF_TOKEN_FILE` / `CIVITAI_TOKEN_FILE` defaults — no extra
config needed.

## Plain `docker run`

Bind-mount the token files yourself:

```bash
docker run -d \
  --name comfyui \
  --gpus all \
  -e PUID=1000 -e PGID=1000 -e TZ=Etc/UTC \
  -p 8188:8188 -p 8189:8189 \
  -v $(pwd)/config:/config \
  -v $(pwd)/models:/models \
  -v $(pwd)/input:/input \
  -v $(pwd)/output:/output \
  -v $(pwd)/custom_nodes:/custom_nodes \
  -v $(pwd)/secrets/hf_token.txt:/run/secrets/huggingface_token:ro \
  -v $(pwd)/secrets/civitai_token.txt:/run/secrets/civitai_token:ro \
  ghcr.io/zachsd/comfyui-docker:latest
```

Or skip the file entirely and pass the token directly (fine for local/trusted
hosts, not recommended for anything shared):

```bash
docker run -d ... -e HF_TOKEN=hf_xxxxxxxxxxxx -e CIVITAI_API_TOKEN=your-key ...
```

## Kubernetes

```bash
kubectl create secret generic huggingface-token \
  --from-literal=token=hf_xxxxxxxxxxxx
kubectl create secret generic civitai-token \
  --from-literal=token=your-civitai-key
```

Mount each as a file volume at the path `HF_TOKEN_FILE` / `CIVITAI_TOKEN_FILE`
point at (or override those env vars to match wherever you mount them). See
[docs/kubernetes.md](kubernetes.md) for a full manifest example.

## What gets authenticated

- **Hugging Face**: on container start, `hf auth login --token` runs once
  (see `root/etc/s6-overlay/s6-rc.d/svc-comfyui/run`). That's picked up
  automatically by every `huggingface_hub`-based tool: `pull-model hf`,
  ComfyUI-Manager's model downloader, `transformers`, `diffusers` — no
  per-tool config needed.
- **CivitAI**: there's no CLI login step — CivitAI's API takes the token as
  a query parameter or `Authorization: Bearer` header per-request. The
  container just exports `CIVITAI_API_TOKEN` so `pull-model civitai` (and
  any custom node that reads that env var) can use it.

## Rotating a token

Docker Compose / plain `docker run`: replace the file contents and restart
the container (`docker compose restart` / `docker restart`).

Kubernetes: `kubectl delete secret <name>` then recreate it, followed by
`kubectl rollout restart deployment/<your-deployment>` — the mounted file
doesn't hot-reload into the already-running process on its own.
