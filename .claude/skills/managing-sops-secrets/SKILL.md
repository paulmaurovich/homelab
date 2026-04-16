---
name: managing-sops-secrets
description: Encrypt, decrypt, edit, and rotate SOPS+age-encrypted secrets in this homelab. Use when the user mentions SOPS, age, encrypting a secret, editing a `.enc.yaml` or `.k8s.enc.yaml` file, creating a Kubernetes Secret that Flux will decrypt, or when CI fails with "NOT encrypted" in the SOPS Encryption Check workflow.
---

# Managing SOPS secrets

All sensitive values in this repo are encrypted with [SOPS](https://github.com/getsops/sops) using a single [age](https://github.com/FiloSottile/age) recipient before they touch Git. Flux decrypts them in-cluster using the `sops-age` Secret in the `flux-system` namespace.

## Conventions that matter

Two filename patterns, each with different encryption scope (see `.sops.yaml`):

| Pattern | Scope | Used for |
|---|---|---|
| `*.k8s.enc.yaml` | Only `data` and `stringData` fields encrypted | Kubernetes `Secret` resources — metadata stays readable so Kustomize can reference the name |
| `*.enc.yaml` | Entire file encrypted | Ansible/Terraform variable files |

Recipient (public): `age1ys5az3gtql0nut2ldf88waz3jkmwzuvfl7gcrn9sja2luvnaud2s6u3834`

Private key on Paul's machine: `~/homelab.agekey` (exported as `SOPS_AGE_KEY_FILE` via `.envrc`; `direnv allow` if not active).

## Creating a new Kubernetes Secret

1. Write the Secret as plaintext YAML at the target path with a `.k8s.enc.yaml` extension — e.g. `k3s/apps/prod/<app>/db-secrets.k8s.enc.yaml`:

    ```yaml
    apiVersion: v1
    kind: Secret
    metadata:
      name: <app>-db-credentials
      namespace: <app>
    type: Opaque
    stringData:
      username: <user>
      password: <pass>
    ```

2. Encrypt in place:

    ```bash
    sops --encrypt --in-place k3s/apps/prod/<app>/db-secrets.k8s.enc.yaml
    ```

3. Add the file to the parent `kustomization.yaml` under `resources:`. Kustomize won't pick it up otherwise.

4. Verify: open the file — `data`/`stringData` values must be unreadable, `metadata` must still be readable, and a `sops:` block must be present at the bottom.

## Editing an existing encrypted file

Never open a `.enc.yaml` in a normal editor and save — the file won't decrypt after that. Always use:

```bash
sops edit k3s/apps/prod/<app>/db-secrets.k8s.enc.yaml
```

SOPS decrypts to a temp file, opens `$EDITOR`, re-encrypts on save, and wipes the temp file.

To just inspect without editing:

```bash
sops --decrypt k3s/apps/prod/<app>/db-secrets.k8s.enc.yaml
```

## Creating a Terraform/Ansible secret file

Use the `*.enc.yaml` (not `.k8s.enc.yaml`) extension so the whole-file rule in `.sops.yaml` applies. Example paths: `terraform/cluster-provisioning/provider-secrets.enc.yaml`, `ansible/playbooks/cluster-provisioning/secrets/k3s-cluster-secrets.enc.yaml`.

## Verifying everything is encrypted (matches CI)

CI runs this in `.github/workflows/sops-encryption-check.yaml` — replicate locally before pushing:

```bash
find . -name "*.enc.yaml" -not -path "./.git/*" -print0 \
  | xargs -0 -I {} sh -c 'grep -q "^sops:" "{}" || echo "NOT encrypted: {}"'
```

Any output = a file will fail CI. Encrypt it before pushing.

## When Flux can't decrypt (fresh cluster or rotated key)

Symptoms: `flux get kustomization` shows `decryption provider: sops: Failed to decrypt ...` on apps or infra.

Fix: re-upload the age key to the cluster:

```bash
./apply-sops-age.sh
```

This is the one-liner at the repo root. It reads `~/homelab.agekey` and recreates the `sops-age` Secret in `flux-system`. Flux picks up the new key on the next reconcile (force it with `flux reconcile kustomization apps --with-source`).

## Rotating the age key (rare, disruptive)

Only do this if the private key is compromised. Outline — ask the user before executing each step:

1. Generate new key: `age-keygen -o ~/homelab.agekey.new`.
2. Update `.sops.yaml` with the new public key.
3. Re-encrypt every `*.enc.yaml` file: `sops updatekeys <file>` for each (script it with `find`).
4. Commit + push (CI must still pass — old and new keys can coexist in `.sops.yaml` during the transition).
5. Replace `~/homelab.agekey` with the new key, re-run `./apply-sops-age.sh`.
6. Once Flux reconciles successfully, remove the old recipient from `.sops.yaml` and re-run `sops updatekeys` everywhere.

## Anti-patterns to catch

- Committing a `.enc.yaml` without the `sops:` trailer — CI will block it, but don't push it in the first place.
- Hand-editing `data:` values in a `.k8s.enc.yaml` — they're base64 ciphertext, not plaintext. Use `sops edit`.
- Creating `secret.yaml` (unencrypted name) for a Kubernetes Secret. Always use the `.k8s.enc.yaml` extension so the creation rule fires.
- Dropping a plaintext copy at `secret.dec.yaml` or similar "for now" — these get committed by accident.
