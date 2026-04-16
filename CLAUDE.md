# CLAUDE.md

Instructions for Claude agents working in this repository. Read this once per session.

## Quick context

This is Paul's personal homelab — a K3s HA cluster on Proxmox VMs, managed GitOps-style with FluxCD. The repo is the **single source of truth**: Flux reconciles cluster state from `main`. No manual `kubectl apply`, no out-of-band changes, no secrets in plaintext. See [README.md](README.md) for the full architecture rationale.

The repo is public on purpose: it's portfolio / proof-of-work. Treat changes like you would a real production environment — small, reviewable, reversible.

## Repository layout

```
ansible/        Cluster bootstrap + node config (K3s, HAProxy, Keepalived, NFS, GPU)
terraform/      Proxmox VM provisioning
k3s/
├── apps/
│   ├── base/           Reusable manifests (deployment, service, namespace) per app
│   └── prod/           Prod overlay (ConfigMaps, PVCs, encrypted secrets)
├── infrastructure/
│   ├── controllers/
│   │   ├── base/       HelmReleases + HelmRepositories (cert-manager, loki, …)
│   │   └── prod/       Prod-specific overrides
│   └── configs/
│       ├── base/       Shared configs (ClusterIssuers, Cloudflare tokens)
│       └── prod/       Prod ingress, Traefik routes, CNPG backup config
└── clusters/prod/      Flux entry points: flux-system/, apps.yaml, infrastructure.yaml
.github/workflows/      CI: kustomize-build, kubernetes-policy-check (Datree), sops-encryption-check
.sops.yaml              SOPS creation rules (age recipient)
renovate.json           Dependency grouping + automerge policy
apply-sops-age.sh       Uploads age key to cluster as flux-system/sops-age secret
.envrc                  direnv: SOPS_AGE_KEY_FILE, KUBECONFIG, ANSIBLE_INVENTORY
```

Flux reconciliation DAG: `apps` (10m) → `infra-controllers` (1h) → `infra-configs` (1h). Everything under `k3s/clusters/prod/` is the Flux entrypoint — don't rename without updating `gotk-sync.yaml`.

## Non-negotiable rules

1. **No `kubectl apply`, `helm install`, or `helm upgrade` against the cluster.** The cluster is a reflection of `main`. If you want a change, it goes through Git. `kubectl get/describe/logs` for *inspection* is fine.
2. **Secrets are always encrypted before commit.** Files matching `*.enc.yaml` must contain a `sops:` block. The `sops-encryption-check` CI job blocks merges otherwise. Never commit a decrypted `.enc.yaml` even temporarily — use `sops edit` or encrypt-in-place.
3. **Don't bump versions by hand.** Renovate owns image tags, Helm chart versions, and Terraform providers. If you see an outdated version, check if a Renovate PR is open before touching it.
4. **No new top-level directories without reason.** Apps go under `k3s/apps/`; cluster services under `k3s/infrastructure/controllers/` or `/configs/`.
5. **Match existing patterns.** Look at a neighbor (jellyfin for apps, loki for HelmReleases) before inventing a new shape.

## Secrets & SOPS

- Age recipient: `age1ys5az3gtql0nut2ldf88waz3jkmwzuvfl7gcrn9sja2luvnaud2s6u3834` (pinned in `.sops.yaml`).
- Private key lives at `~/homelab.agekey` on Paul's machine; exported via `.envrc` as `SOPS_AGE_KEY_FILE`.
- Two file-naming conventions, chosen by `.sops.yaml` regex:
  - `*.k8s.enc.yaml` — Kubernetes Secrets; only `data` / `stringData` fields are encrypted (metadata stays readable for Kustomize).
  - `*.enc.yaml` — Terraform/Ansible variable files; entire file encrypted.
- Flux decrypts in-cluster using the `sops-age` Secret in `flux-system`. If a fresh cluster can't decrypt, re-run `./apply-sops-age.sh`.

See the `managing-sops-secrets` skill for the encrypt/edit/rotate workflow.

## Adding or changing manifests

- **New app:** follow `k3s/apps/base/jellyfin/` + `k3s/apps/prod/jellyfin/`. Append to `k3s/apps/base/kustomization.yaml` AND `k3s/apps/prod/kustomization.yaml`. The `adding-flux-app` skill has the exact template.
- **New cluster service (Helm chart):** follow `k3s/infrastructure/controllers/base/loki/`. See `adding-helmrelease`.
- **New ingress route or middleware:** `k3s/infrastructure/configs/prod/traefik/`.
- **Every new directory needs a `kustomization.yaml`** listing its resources, and its parent's `kustomization.yaml` needs to reference it. The `kustomize-build` CI job will fail otherwise.

## Validate before pushing

Run locally before opening a PR:

```bash
kustomize build k3s/apps/prod > /dev/null
kustomize build k3s/infrastructure/controllers/prod > /dev/null
kustomize build k3s/infrastructure/configs/prod > /dev/null
find . -name "*.enc.yaml" -not -path "./.git/*" -exec grep -L "^sops:" {} +
```

The three `kustomize build` calls are exactly what `kustomize-build.yaml` runs in CI. The `find` replicates the SOPS check. See the `validating-manifests` skill.

## Working with Flux (inspection only)

```bash
flux get kustomization -A           # Reconciliation status
flux get helmrelease -A
flux logs --all-namespaces --level=error --since=30m
flux reconcile source git flux-system   # Force pull of latest main
flux reconcile kustomization apps --with-source
```

`flux suspend` / `flux resume` are allowed for temporary pauses, but always resume before ending a session. See `troubleshooting-flux` for a triage flow.

## Git & PR conventions

- Branch off `main`. Conventional commits (`feat:`, `fix:`, `chore(deps):`, …) — see recent `git log`.
- PRs are the unit of change. Renovate PRs automerge on green CI for non-major updates.
- CI must be green before merge: `Kustomize Build`, `Kubernetes Policy Check` (Datree, advisory), `SOPS Encryption Check`.
- After merge, Flux reconciles within 10 minutes for apps, 1 hour for infra. Use `flux reconcile` to speed up a specific change if needed.

## Common gotchas

- **Kustomize silently skips files not listed in `kustomization.yaml`.** A new `*.yaml` that isn't referenced will never reach the cluster — and CI won't flag it. Always update the parent `kustomization.yaml`.
- **HelmRelease `chart.spec.sourceRef.namespace` matters.** The `HelmRepository` is usually in `monitoring` or `flux-system`; copy from an existing release.
- **Flux won't re-apply an identical manifest.** If something looks stuck, check `flux get kustomization` for error status before assuming it's a timing issue.
- **SOPS metadata is encrypted too.** Never edit `.enc.yaml` files by hand — use `sops edit`. A hand-edited file won't decrypt.
- **`prune: true` is set on all Kustomizations.** Removing a resource from Git deletes it from the cluster. Double-check before deleting manifests for stateful workloads (PVCs, CNPG Clusters).
- **Renovate groups exist for a reason** (`jellyfin-stack`, `arr-stack`, `loki-promtail`). Don't split these updates manually — they're coupled by API compatibility.

## Tone

Paul knows his stack. Explain the *why* only when it's non-obvious or when you're suggesting something unusual. Match the terseness of existing manifests and commit messages. When in doubt, read a neighbor and do the same thing.
