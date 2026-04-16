---
name: validating-manifests
description: Run the exact local validation checks that CI runs — kustomize build on all three overlays plus the SOPS encryption check — before pushing a commit. Use before opening a PR, when the user asks to "validate", "lint", "check before pushing", "make sure CI will pass", or after any change to `k3s/` manifests or `.enc.yaml` files.
---

# Validating manifests

Three CI jobs gate every PR: `Kustomize Build`, `Kubernetes Policy Check` (Datree, advisory), and `SOPS Encryption Check`. Running their logic locally before pushing saves a round-trip and catches the vast majority of problems the cluster would also fail on.

## The pre-push checklist

Run these from the repo root. Each line is cheap; run them all.

```bash
# 1. Kustomize overlays — these are exactly what .github/workflows/kustomize-build.yaml runs
kustomize build k3s/apps/prod > /dev/null
kustomize build k3s/infrastructure/controllers/prod > /dev/null
kustomize build k3s/infrastructure/configs/prod > /dev/null

# 2. SOPS encryption — mirrors .github/workflows/sops-encryption-check.yaml
find . -name "*.enc.yaml" -not -path "./.git/*" -print0 \
  | xargs -0 -I {} sh -c 'grep -q "^sops:" "{}" || echo "NOT encrypted: {}"'
```

Pass criteria:

- The three `kustomize build` commands all exit 0 with no stderr output. Any error = CI will fail on the same overlay with the same error.
- The `find` prints nothing. Any output = a file is unencrypted and will fail CI.

## What each check catches

**`kustomize build k3s/apps/prod`** — resolves every app's base + prod overlay together.
- Missing file referenced in a `kustomization.yaml`
- Missing app folder listed in a parent `kustomization.yaml`
- Duplicate resource names across bases
- Malformed YAML
- Invalid patch targets

**`kustomize build k3s/infrastructure/controllers/prod`** — every HelmRelease, HelmRepository, and operator.
- HelmRelease referencing a HelmRepository that doesn't exist (or wrong namespace)
- Missing `namespace.yaml` when the chart expects the namespace pre-created
- Values file referenced via `valuesFrom` but the ConfigMap/Secret isn't in the kustomization

**`kustomize build k3s/infrastructure/configs/prod`** — Traefik ingress routes, middlewares, cert-manager issuers, CNPG backup configs.
- IngressRoute pointing at a Service that isn't in scope
- Certificate referencing a ClusterIssuer that isn't in base
- ScheduledBackup referencing a Cluster (CNPG) that doesn't exist

**SOPS check** — any `*.enc.yaml` without the trailing `sops:` block. If you hand-edited an encrypted file or forgot to run `sops --encrypt`, this catches it before GitHub does.

## What's NOT caught by local validation

These pass `kustomize build` but still fail at reconcile time:

- **Wrong `sourceRef.namespace` on a HelmRelease** — renders fine, fails when Flux tries to fetch the chart. Confirm by comparing to a working neighbor.
- **Image tag doesn't exist** — `kustomize build` doesn't pull images. Renovate or a typo check will catch it; otherwise you'll see it in `kubectl describe pod` after reconcile.
- **Datree policy violations** (missing resource limits, mutable tags, missing security context). The `kubernetes-policy-check` job is **advisory** — it won't block merge, but it will surface suggestions in CI logs. You can run it locally if you have `datree` installed; skip otherwise.
- **SOPS decryption at runtime** — local validation only checks *that* files are encrypted, not that the cluster has the right key. See the `troubleshooting-flux` skill if Flux reports decryption failures after merge.

## Running the checks as a single command

```bash
(set -e
 for overlay in k3s/apps/prod k3s/infrastructure/controllers/prod k3s/infrastructure/configs/prod; do
   echo "=== $overlay ==="
   kustomize build "$overlay" > /dev/null
 done
 echo "=== SOPS check ==="
 bad=$(find . -name "*.enc.yaml" -not -path "./.git/*" -print0 | xargs -0 -I {} sh -c 'grep -q "^sops:" "{}" || echo {}')
 if [ -n "$bad" ]; then echo "NOT encrypted:"; echo "$bad"; exit 1; fi
 echo "All checks passed."
)
```

## When a check fails

- **`accumulating resources: <path>: evalsymlink failure`** — a `kustomization.yaml` references a file or folder that doesn't exist. Fix the path.
- **`no matches for Id <kind>` (on CRDs)** — often fine locally if the CRD isn't installed. CI uses the same `kustomize build` without cluster access, so this usually still works. If it breaks CI, you likely need `spec.install.crds: Create` on a HelmRelease, or a CRD manifest in base.
- **`duplicate resource <name>`** — two bases define the same resource. Either remove one or rename it.
- **`NOT encrypted: <path>`** — run `sops --encrypt --in-place <path>` or `sops edit <path>` and save.

## One more thing before pushing

Scan the diff for anything that *looks* like a secret but isn't in a `.enc.yaml`:

```bash
git diff --cached | grep -iE '(password|token|secret|api[_-]?key|bearer|authorization).*[:=]' || true
```

False positives are common (env var names, labels), but a real leak surfaces here. If there's a genuine secret value, move it into a `.k8s.enc.yaml` and encrypt before committing — see the `managing-sops-secrets` skill.
