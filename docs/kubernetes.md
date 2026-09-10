# Running on Kubernetes

A minimal manifest — namespace, Deployment, Service, two optional Secrets.
Adjust the hostPath values (or swap in a PVC/StorageClass) for your cluster.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: comfyui
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: comfyui
  namespace: comfyui
spec:
  replicas: 1
  selector:
    matchLabels: { app: comfyui }
  strategy: { type: Recreate }
  template:
    metadata:
      labels: { app: comfyui }
    spec:
      containers:
        - name: comfyui
          image: ghcr.io/zachsd/comfyui-docker:latest
          env:
            - { name: PUID, value: "1000" }
            - { name: PGID, value: "1000" }
            - { name: TZ, value: "Etc/UTC" }
            - { name: ENABLE_SAGE_ATTENTION, value: "true" }
            - { name: COMFY_MCP_ENABLED, value: "true" }
          ports:
            - { containerPort: 8188, name: comfyui }
            - { containerPort: 8189, name: mcp }
          resources:
            requests: { memory: 16Gi, nvidia.com/gpu: 1 }
            limits: { memory: 48Gi, nvidia.com/gpu: 1 }
          volumeMounts:
            - { mountPath: /config, name: config }
            - { mountPath: /models, name: models }
            - { mountPath: /input, name: input }
            - { mountPath: /output, name: output }
            - { mountPath: /custom_nodes, name: custom-nodes }
            - { mountPath: /run/secrets/huggingface_token, name: hf-token, subPath: token, readOnly: true }
            - { mountPath: /run/secrets/civitai_token, name: civitai-token, subPath: token, readOnly: true }
      volumes:
        - name: config
          hostPath: { path: /data/comfyui/config, type: DirectoryOrCreate }
        - name: models
          hostPath: { path: /data/comfyui/models, type: DirectoryOrCreate }
        - name: input
          hostPath: { path: /data/comfyui/input, type: DirectoryOrCreate }
        - name: output
          hostPath: { path: /data/comfyui/output, type: DirectoryOrCreate }
        - name: custom-nodes
          hostPath: { path: /data/comfyui/custom_nodes, type: DirectoryOrCreate }
        - name: hf-token
          secret: { secretName: huggingface-token, optional: true }
        - name: civitai-token
          secret: { secretName: civitai-token, optional: true }
---
apiVersion: v1
kind: Service
metadata:
  name: comfyui
  namespace: comfyui
spec:
  selector: { app: comfyui }
  ports:
    - { name: comfyui, port: 8188, targetPort: 8188 }
    - { name: mcp, port: 8189, targetPort: 8189 }
```

Create the (optional) secrets before or after applying — they're
`optional: true` so the pod starts either way:

```bash
kubectl create secret generic huggingface-token -n comfyui --from-literal=token=hf_xxxxxxxxxxxx
kubectl create secret generic civitai-token -n comfyui --from-literal=token=your-civitai-key
kubectl rollout restart deployment/comfyui -n comfyui   # picks up a freshly-created secret
```

## GPU scheduling

This assumes the [NVIDIA GPU Operator](https://github.com/NVIDIA/gpu-operator)
(or an equivalent device plugin) is installed on the cluster so
`nvidia.com/gpu` is a schedulable resource. If you're running GPU
time-slicing across multiple pods (e.g. sharing one GPU between ComfyUI and
an LLM server), see the operator's docs for `ClusterPolicy` device-plugin
config — out of scope for this image.

## NodePort / Ingress

Add a `NodePort` Service (or your own Ingress) pointing at the `comfyui`
Service's `comfyui` and/or `mcp` ports if you need LAN-wide or external
access rather than in-cluster only. Example NodePort:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: comfyui-nodeport
  namespace: comfyui
spec:
  type: NodePort
  selector: { app: comfyui }
  ports:
    - { name: comfyui, port: 8188, targetPort: 8188, nodePort: 30818 }
    - { name: mcp, port: 8189, targetPort: 8189, nodePort: 30819 }
```

## A real-world deployment for reference

[zachsd/comfyui-dgx-spark](https://github.com/zachsd/comfyui-dgx-spark) is a
concrete, in-production k3s deployment of an earlier iteration of this setup
(single-node cluster, hostPath volumes, NodePort services) — useful as a
worked example, though this repo's image supersedes its custom Dockerfile.
