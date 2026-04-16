---
name: adding-helmrelease
description: Add a new Flux HelmRelease (and HelmRepository if needed) under k3s/infrastructure/controllers/ to deploy a Helm-packaged cluster service. Use when the user wants to install an operator, ingress controller, observability stack, or any upstream Helm chart — e.g. "add cert-manager", "install kube-prometheus-stack", "deploy <operator>". For single-Deployment self-hosted apps, use the `adding-flux-app` skill instead.
---

# Adding a HelmRelease

Cluster services backed by Helm charts live under `k3s/infrastructure/controllers/`. Flux's `infra-controllers` Kustomization reconciles `k3s/infrastructure/controllers/prod`, which layers over `base/`. Everything here depends on `apps` having reconciled first (see `k3s/clusters/prod/infrastructure.yaml`).

## Directory shape

Mirror `k3s/infrastructure/controllers/base/loki/`:

```
k3s/infrastructure/controllers/base/<name>/
├── namespace.yaml
├── helm-release.yaml        # HelmRelease CR
├── helm-repository.yaml     # HelmRepository CR (if the chart source is new)
└── kustomization.yaml       # resources: [./namespace.yaml, ./helm-repository.yaml, ./helm-release.yaml]
```

If the chart lives in an existing `HelmRepository` (grafana, fluxcd, cert-manager, bitnami, etc. — grep `kind: HelmRepository` to find them), skip `helm-repository.yaml` and reference the existing one by name + namespace.

A `prod/` overlay at `k3s/infrastructure/controllers/prod/<name>/` is only needed when prod values differ from base (extra resources, patched values, prod-specific secrets). Many services have no prod overlay at all.

## Steps

1. **Find the chart.** Official Helm repo URL + chart name + latest stable version. Prefer OCI registries (`oci://...`) when available — Renovate handles OCI refs cleanly and `flux` disables digest pinning for them (see `renovate.json`).

2. **Pick a neighbor** with the same shape:
   - OCI chart: `cloudflared` or similar.
   - Classic HelmRepository chart: `loki` (grafana repo), `cert-manager`.
   - Operator with CRDs: `cloudnativepg`, `intel-device-plugin-operator`.

3. **Create `k3s/infrastructure/controllers/base/<name>/`:**

    `namespace.yaml`:
    ```yaml
    apiVersion: v1
    kind: Namespace
    metadata:
      name: <name>
    ```

    `helm-repository.yaml` (only if chart source is new to the repo):
    ```yaml
    apiVersion: source.toolkit.fluxcd.io/v1
    kind: HelmRepository
    metadata:
      name: <repo-short-name>
      namespace: <name>   # or a shared one like `monitoring`, matching neighbors
    spec:
      interval: 1h
      url: https://<chart-host>
    ```

    `helm-release.yaml`:
    ```yaml
    apiVersion: helm.toolkit.fluxcd.io/v2
    kind: HelmRelease
    metadata:
      name: <name>
      namespace: <name>
    spec:
      interval: 10m
      timeout: 5m
      chart:
        spec:
          chart: <chart-name>
          version: <x.y.z>
          sourceRef:
            kind: HelmRepository
            name: <repo-short-name>
            namespace: <repo-namespace>   # must match the HelmRepository, not the release
      values:
        # minimal values — override only what's needed
    ```

    `kustomization.yaml`:
    ```yaml
    resources:
      - ./namespace.yaml
      - ./helm-repository.yaml   # omit if reusing an existing repo
      - ./helm-release.yaml
    ```

4. **Register in the parent kustomization:** append `- ./<name>` to `k3s/infrastructure/controllers/base/kustomization.yaml`.

5. **Prod overlay (only if needed):** create `k3s/infrastructure/controllers/prod/<name>/kustomization.yaml` that references `../../base/<name>` plus any prod-specific patches, and append `- ./<name>` to `k3s/infrastructure/controllers/prod/kustomization.yaml`. Skip this if base is sufficient — many services here do.

6. **Validate locally:**

    ```bash
    kustomize build k3s/infrastructure/controllers/prod > /dev/null
    ```

    If it fails with "no matches for kind HelmRelease" that means Flux CRDs aren't in your local toolchain — ignore; CI uses a different validator. Structural errors ("accumulating resources", missing files) are real and must be fixed.

7. **Commit + PR.** On merge, Flux reconciles `infra-controllers` on a 1h interval. To push it immediately:

    ```bash
    flux reconcile source git flux-system
    flux reconcile kustomization infra-controllers --with-source
    flux get helmrelease -A <name>
    ```

## Values: where to put them

- **Small, stable values** (a few dozen lines): inline under `spec.values` in `helm-release.yaml`. This is what most releases in this repo do (see `loki`, `traefik`).
- **Large/sensitive values**: use `spec.valuesFrom` to pull from a ConfigMap or Secret. Reference by name; put the CM/Secret in the same namespace and list it in the `kustomization.yaml`. Encrypt secrets as `*.k8s.enc.yaml` (see the `managing-sops-secrets` skill).

## Common mistakes

- **Wrong `sourceRef.namespace`.** The `HelmRepository` often lives in a shared namespace (`monitoring`, `flux-system`) while the HelmRelease lives in its own. Copy both from a working neighbor — getting this wrong is the #1 reason a HelmRelease shows `chart reconciliation failed`.
- **Forgetting to add the folder to the parent `kustomization.yaml`.** Kustomize silently skips it; Flux never deploys anything; no CI error. Always update the parent.
- **CRDs not installed yet.** If the chart ships CRDs, set `spec.install.crds: Create` and `spec.upgrade.crds: CreateReplace` in the HelmRelease. Otherwise operators depending on those CRDs will fail to start.
- **Pinning `version:` to `*` or a range.** Renovate wants a concrete version to diff against. Always pin `x.y.z`. Renovate will open a PR when a newer version is available.
- **Namespace not created.** The `HelmRelease` must have a target namespace that exists — include `namespace.yaml` in the kustomization unless you're targeting `kube-system` or another shared namespace.

## When a HelmRelease fails to reconcile

```bash
flux get helmrelease -A           # find the failing release
flux logs --kind=HelmRelease --name=<name> --namespace=<ns> --since=15m
kubectl describe helmrelease <name> -n <ns>
kubectl get events -n <ns> --sort-by=.lastTimestamp | tail -30
```

See the `troubleshooting-flux` skill for the full triage flow.
