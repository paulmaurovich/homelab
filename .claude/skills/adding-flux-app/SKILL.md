---
name: adding-flux-app
description: Add a new self-hosted application to the cluster by creating base + prod overlays under k3s/apps/. Use when the user asks to "deploy a new app", "add <app> to the cluster", "self-host <something>", or otherwise wants a new workload running. This skill covers raw-manifest apps (Deployment/Service/PVCs) — for Helm-chart-based infrastructure services, use the `adding-helmrelease` skill instead.
---

# Adding a Flux app

Apps live under `k3s/apps/` with a two-layer Kustomize pattern: a `base/` with the portable manifests, and a `prod/` overlay with environment-specific pieces (PVCs, ConfigMap values, encrypted secrets). Flux's `apps` Kustomization points at `k3s/apps/prod`, which references `../base/<app>`.

## When to use raw manifests vs a HelmRelease

- **Raw manifests (this skill)** — single-container apps, arr-stack tools, most self-hosted web apps. Think `jellyfin`, `sonarr`, `vaultwarden`, `gatus`.
- **HelmRelease** — multi-component systems with upstream charts (observability stacks, operators, ingress controllers). Use `adding-helmrelease`.

If in doubt, check if an official/linuxserver container image exists and the app is a single Deployment — if yes, use raw manifests.

## Directory shape to create

Mirror `k3s/apps/base/jellyfin/` and `k3s/apps/prod/jellyfin/`:

```
k3s/apps/base/<app>/
├── namespace.yaml
├── deployment.yaml
├── service.yaml
└── kustomization.yaml   # resources: [./namespace.yaml, ./deployment.yaml, ./service.yaml]

k3s/apps/prod/<app>/
├── config.yaml          # ConfigMap with env (TZ, PUID, PGID, app-specific vars)
├── storage-<name>.yaml  # one PVC per mount path
├── *.k8s.enc.yaml       # encrypted Secrets (optional)
└── kustomization.yaml   # resources: all of the above; typically also `../../base/<app>` if base is referenced via overlay
```

Two reference patterns exist in the repo — check both before copying:

- **Overlay style** (jellyfin): `prod/jellyfin/kustomization.yaml` only lists prod-specific resources; base is merged via the parent `prod/kustomization.yaml` alongside `../base/<app>`. Read `k3s/apps/base/kustomization.yaml` — it lists every `./<app>` folder.
- **Direct base reference**: some apps reference `../../base/<app>` from their prod `kustomization.yaml`.

Match whichever the neighbor app uses so patches and references stay consistent.

## Steps

1. **Pick a neighbor to clone from.** For an arr-stack app: copy `sonarr`. For a simple web UI: copy `it-tools` or `miniflux`. For media with GPU needs: `jellyfin`. Copy the directory shape; don't start from scratch.

2. **Create `k3s/apps/base/<app>/`** with:
   - `namespace.yaml` — `apiVersion: v1, kind: Namespace, metadata.name: <app>`.
   - `deployment.yaml` — image pinned by tag (Renovate will pin the digest). PUID/PGID/TZ from the ConfigMap in prod. Resource requests if known.
   - `service.yaml` — `ClusterIP` on the app's port. Traefik picks it up via IngressRoute in `infrastructure/configs/prod/traefik/`.
   - `kustomization.yaml` listing the three resources.

3. **Create `k3s/apps/prod/<app>/`** with:
   - `config.yaml` — `ConfigMap` with prod env values.
   - `storage-*.yaml` — one PVC per mount (config, cache, media via NFS, etc.). Copy storageClassName from a neighbor: `local-path` for app state, `nfs-client` for shared media.
   - `<app>-secrets.k8s.enc.yaml` if secrets are needed — create plaintext first, then `sops --encrypt --in-place`. See the `managing-sops-secrets` skill.
   - `kustomization.yaml` listing everything in this folder.

4. **Register the app in both parent kustomizations:**
   - Append `- ./<app>` to `k3s/apps/base/kustomization.yaml`.
   - Append `- ./<app>` to `k3s/apps/prod/kustomization.yaml` (read the file first — it may follow a slightly different pattern).

5. **Add the ingress route** (if the app should be reachable externally) in `k3s/infrastructure/configs/prod/traefik/ingress-routes.yaml`. Copy the shape of an existing route. Hostnames route through Cloudflare Tunnels + Traefik — no port-forwarding needed.

6. **Validate locally** (same checks CI runs):

    ```bash
    kustomize build k3s/apps/prod > /dev/null
    kustomize build k3s/infrastructure/configs/prod > /dev/null
    ```

    Any error here ("accumulating resources", "no matches for kind", "field not declared") = fix before pushing.

7. **Commit with a conventional message** (`feat(apps): add <app>`) and open a PR. CI runs Kustomize Build + Datree policy check + SOPS encryption check. Once merged, Flux picks it up within ~10 minutes. Speed it up with `flux reconcile kustomization apps --with-source` if needed.

## Common mistakes

- Forgetting to add the new folder to `k3s/apps/base/kustomization.yaml` or `k3s/apps/prod/kustomization.yaml`. The app just silently doesn't deploy — no CI error, no Flux error. Always update both.
- Wrong `storageClassName`. `local-path` is node-local (lost if the node dies); use it for caches. `nfs-client` for anything that needs to survive node loss or be shared. Check with `kubectl get sc`.
- Hardcoding versions in `image: foo:1.2.3` — fine, Renovate pins and updates them. Don't use `:latest`; Renovate can't diff it.
- Creating a `Secret` without the `.k8s.enc.yaml` extension. `.sops.yaml`'s creation rule won't fire, encryption won't happen the way Flux expects. See `managing-sops-secrets`.
- Putting the PVC in `base/`. PVC sizes are environment-specific — keep them in `prod/` so a future staging overlay can differ.

## What Renovate needs

For Renovate to track your app's image, just pin a real tag (`image: lscr.io/linuxserver/sonarr:4.0.11`). If the image belongs to a coupled group (arr-stack, jellyfin-stack, loki-promtail, cloudnative-pg), check `renovate.json` — you may need to add the package to an existing group so it updates together with its siblings.
