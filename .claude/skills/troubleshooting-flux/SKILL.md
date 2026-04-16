---
name: troubleshooting-flux
description: Diagnose why a Flux Kustomization or HelmRelease isn't reconciling, why a change in Git hasn't reached the cluster, or why resources are stuck/erroring. Use when the user says something like "Flux isn't picking up my change", "the HelmRelease is failing", "kustomization shows not ready", "my PR merged but nothing changed", "app isn't deployed", or when they share Flux error output.
---

# Troubleshooting Flux

Flux has three moving parts: a **GitRepository source** that polls `main`, **Kustomizations** that render + apply manifests, and **HelmReleases** that install charts. A symptom can live in any of them — the trick is to walk the chain top-down and find the first red flag.

## The 30-second triage

Run these three first — one of them almost always reveals the problem:

```bash
flux get sources git -A
flux get kustomization -A
flux get helmrelease -A
```

Look at the `READY` column. `True` = healthy. `False` = error, read `STATUS` for the message. `Unknown` = in-progress or never reconciled.

Common patterns:

| `READY` / `STATUS` fragment | What it means | Next step |
|---|---|---|
| Source `False`, `failed to checkout`, `authentication required` | Flux can't reach GitHub | Check `flux-system` pods, network, any deploy key rotation |
| Kustomization `False`, `decryption provider: sops: Failed to decrypt` | Age key missing/wrong in cluster | `./apply-sops-age.sh`, see `managing-sops-secrets` |
| Kustomization `False`, `accumulating resources`, `no such file` | A `kustomization.yaml` references a missing file/folder | Run `kustomize build <path>` locally on the failing path |
| Kustomization `False`, `dependency ... is not ready` | Parent Kustomization is the real problem | Work on the dependency first (apps → infra-controllers → infra-configs) |
| HelmRelease `False`, `chart reconciliation failed` | HelmRepository/HelmChart source broken or chart version missing | `flux get source chart -A` + `flux get source helm -A` |
| HelmRelease `False`, `install retries exhausted` | Chart values wrong, CRDs missing, or target namespace issue | `kubectl describe helmrelease` + `kubectl logs` of the chart's pods |
| Kustomization `Unknown` forever | Never reconciled | `flux reconcile kustomization <name> --with-source` |

## Deeper: "my commit merged but nothing changed"

1. **Is Flux actually pulling?**

    ```bash
    flux get source git flux-system
    ```

    Compare the commit SHA in `REVISION` with `git rev-parse origin/main`. If stale, force:

    ```bash
    flux reconcile source git flux-system
    ```

2. **Is the Kustomization applying?**

    ```bash
    flux get kustomization -A
    ```

    `apps` runs every 10m; `infra-controllers` and `infra-configs` run every 1h. If your change is in infra and you're impatient:

    ```bash
    flux reconcile kustomization infra-controllers --with-source
    ```

3. **Is the resource actually in the rendered output?**

    ```bash
    kustomize build k3s/apps/prod | grep -A3 "name: <your-resource>"
    ```

    If not there → you probably forgot to add the new file/folder to a parent `kustomization.yaml`. Kustomize silently skips unreferenced files. Fix by appending to the right `kustomization.yaml` and re-committing.

4. **Is it in the cluster?**

    ```bash
    kubectl get <kind> -A | grep <name>
    kubectl describe <kind> <name> -n <ns>
    ```

    If `describe` shows `managed-by: kustomize-controller`, Flux did apply it — the problem is in the resource itself (image pull, readiness probe, etc.), not in Flux.

## HelmRelease-specific debugging

```bash
flux logs --kind=HelmRelease --name=<name> --namespace=<ns> --since=30m --level=error
kubectl describe helmrelease <name> -n <ns>
kubectl get events -n <ns> --sort-by=.lastTimestamp | tail -40
```

If values look wrong, render locally (values.yaml differs from what's in Git):

```bash
# See what Flux will render — requires flux CLI + chart cached
flux get helmchart -A   # find the HelmChart CR
kubectl get helmchart <name> -n <ns> -o yaml
```

For chart version / source issues:

```bash
flux get source helm -A       # HelmRepository state
flux get source chart -A      # Fetched chart state
```

## Decryption failures

If the message mentions `sops` or `age`:

```bash
kubectl get secret -n flux-system sops-age    # must exist
flux reconcile kustomization apps --with-source
```

If the secret exists but decryption still fails, the key doesn't match the recipient in `.sops.yaml`. Rerun `./apply-sops-age.sh` with the correct `~/homelab.agekey`. See the `managing-sops-secrets` skill for rotation.

## Dependency chain recap

Cluster Kustomizations (see `k3s/clusters/prod/`):

```
apps              → k3s/apps/prod              (interval 10m)
infra-controllers → k3s/infrastructure/controllers/prod   (interval 1h, dependsOn: apps)
infra-configs     → k3s/infrastructure/configs/prod       (interval 1h, dependsOn: infra-controllers)
```

If `apps` is red, nothing below it reconciles. Fix the top-most red Kustomization first.

## Tools you can use freely

Read-only kubectl is always allowed for inspection:

```bash
kubectl get kustomization,helmrelease,gitrepository,helmrepository -A
kubectl describe <kind> <name> -n <ns>
kubectl logs -n flux-system deploy/kustomize-controller --since=30m --tail=200
kubectl logs -n flux-system deploy/helm-controller --since=30m --tail=200
kubectl logs -n flux-system deploy/source-controller --since=30m --tail=200
```

`flux suspend` / `flux resume` are okay for pausing reconciliation during debugging — **always resume before ending the session.**

## What NOT to do

- Don't `kubectl apply -f` to fix a manifest. The cluster is reconciled from Git; your change will be overwritten within minutes, and you'll have just fixed a symptom. Commit to Git instead.
- Don't `kubectl delete` a stuck resource without understanding why it's stuck. `prune: true` means deleting from Git deletes from cluster — if the Git source is fine, deleting the resource just makes Flux recreate it. If it's not fine, deleting masks the real bug.
- Don't `helm upgrade` a HelmRelease manually. Flux owns that release and will revert. Fix `values:` in `helm-release.yaml`, commit.
- Don't disable `prune: true` to "save" a resource. Remove it from Git if you want it gone; keep it in Git if you want it. No middle ground.

## End with a clean handoff

After debugging, leave this output in the conversation so the user has a clean record:

```bash
flux get kustomization -A
flux get helmrelease -A
```

Both should be all `True` — if not, clearly state what's still red and why.
