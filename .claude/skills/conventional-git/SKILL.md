---
name: conventional-git
description: Branch and commit naming conventions for this homelab. Follow these rules whenever creating branches or writing commit messages. Enforces the Conventional Branch and Conventional Commit specifications for this repository.
when_to_use: "creating a branch, naming a branch, making a commit, writing a commit message, git commit, git checkout, commit format, branch format, branch name, how to commit, how to name a branch"
user-invocable: true
---

# Conventional Git — Branch & Commit Conventions

Apply these rules whenever creating branches or composing commit messages.
If you cannot categorize a commit, it is doing too much — split it.

---

## Hard Constraints

- **Never** add `Co-Authored-By:`, `Generated-by:`, or any trailer that attributes
  authorship or assistance to an AI, tool, or model (Claude, Copilot, etc.).
- **Never** mention AI involvement anywhere in a commit message — not in the subject, body,
  or footer. The commit represents the human author's work.
- Footers are only for `BREAKING CHANGE` or peer metadata (`Reviewed-by:`) when explicitly
  requested. This repo has no issue tracker, so issue-ref footers (`Refs:`, `Fixes:`) do not apply.

---

## Branches

Format:

```
type/description
```

No ticket prefix — this homelab has no external ticket system.

### Branch Types

| Type          | Purpose                                                              | Example                                |
| ------------- | -------------------------------------------------------------------- | -------------------------------------- |
| `main`        | Primary integration branch; Flux reconciles from here                | —                                      |
| `feature/`    | Adding something new that did not exist before (**not** `feat/`)     | `feature/add-audiobookshelf`           |
| `fix/`        | Fixing something broken; normal flow                                 | `fix/traefik-middleware-order`         |
| `hotfix/`     | Urgent production fix; cut from `main`, merged back immediately      | `hotfix/sops-age-key-rotation`         |
| `chore/`      | No runtime behavior change: deps, CI, docs, formatting, renovate     | `chore/bump-cert-manager-1.16`         |

There is no `release/` branch — this is a GitOps homelab with a single `prod` environment reconciled continuously from `main`. Versioning happens per-component via Renovate, not per-repo.

### Naming Rules

| Rule                                | Correct                          | Incorrect                        |
| ----------------------------------- | -------------------------------- | -------------------------------- |
| Lowercase only                      | `feature/add-audiobookshelf`     | `feature/Add-Audiobookshelf`     |
| Hyphens as word separators          | `fix/fix-traefik-route`          | `fix/fix_traefik_route`          |
| No spaces                           | `feature/add-lazylibrarian`      | `feature/add lazylibrarian`      |
| No consecutive hyphens              | `feature/add-gatus`              | `feature/add--gatus`             |
| No leading or trailing hyphens      | `feature/add-gatus`              | `feature/-add-gatus`             |
| No trailing dots                    | `chore/bump-loki-6.55`           | `chore/bump-loki-6.55.`          |
| Alphanumerics, hyphens, dots only   | `chore/update-k3s-v1.32`         | `chore/update-k3s@v1.32`         |

### Examples

```
feature/add-audiobookshelf
feature/add-postgres-scheduled-backups
fix/traefik-ingress-route-for-grafana
fix/cloudflared-tunnel-restart-loop
hotfix/sops-age-key-rotation
chore/bump-cert-manager-1.16
chore/renovate-group-media-stack
```

---

## Commits

Format:

```
<type>(<scope>): <description>

[optional body — one sentence]

[optional footer(s)]
```

### Parts

| Part          | Required | Rules                                                                                   |
| ------------- | -------- | --------------------------------------------------------------------------------------- |
| `type`        | Yes      | One of the defined types below                                                          |
| `scope`       | No       | Noun in parentheses describing the affected area, e.g. `(flux)`, `(apps)`, `(sops)`     |
| `description` | Yes      | Lowercase, imperative mood, no trailing period, ≤72 chars total with prefix            |
| `body`        | No       | **One sentence.** One blank line after description. Explains **why**, not what.         |
| `footer`      | No       | One blank line after body. Used for `BREAKING CHANGE` only.                             |

### Types

| Type       | Use When                                              |
| ---------- | ----------------------------------------------------- |
| `feature`  | Introducing new functionality — new app, new controller, new CI job (**not** `feat`) |
| `fix`      | Patching a bug or broken manifest                     |
| `refactor` | Restructuring manifests — no behavior change (e.g. moving a resource between overlays) |
| `docs`     | Documentation changes only (README, CLAUDE.md, skills, inline comments) |
| `style`    | YAML formatting, whitespace, linting — no logic change |
| `build`    | Changes to Terraform providers, Ansible roles, base image pinning |
| `ci`       | GitHub Actions workflow changes                       |
| `chore`    | Housekeeping — Renovate bumps, minor config, cleanup that fits none of the above |

One commit, one type. If you cannot pick one, the commit is doing too much — split it.

### Scope

Scope narrows the context to a subsystem. Defined per this repo:

**GitOps / Kubernetes:**
`flux`, `apps`, `infra`, `controllers`, `configs`, `traefik`, `cert-manager`, `cloudflared`, `loki`, `grafana`, `cnpg`, `redis`, `tailscale`, `nfs`, …

**Per-app scopes** (when a change is scoped to one workload):
`jellyfin`, `sonarr`, `radarr`, `prowlarr`, `sabnzbd`, `gatus`, `vaultwarden`, `paperless-ngx`, `audiobookshelf`, `beszel`, …

**Infrastructure / tooling:**
`terraform`, `ansible`, `haproxy`, `keepalived`, `sops`, `renovate`, `claude`, …

**CI / meta:**
`ci`, `workflows`, `docs`, `readme`

Pick the narrowest scope that still captures the change. `feature(jellyfin)` beats `feature(apps)` when only jellyfin changes.

### Breaking Changes

For a homelab, "breaking" means: requires manual intervention beyond a Flux reconcile
(e.g. PVC migration, manual Talos config apply, age key rotation, namespace deletion).

Use `!` in the type line (preferred):

```
refactor(cnpg)!: migrate postgres storage to local-path
```

Or use a footer:

```
BREAKING CHANGE: requires manual PVC re-creation; see runbook in docs/.
```

### Rules

| Rule                        | Correct                         | Incorrect                       |
| --------------------------- | ------------------------------- | ------------------------------- |
| Type lowercase              | `feature:`                      | `Feature:`                      |
| Space after colon           | `fix: resolve bug`              | `fix:resolve bug`               |
| Description lowercase       | `feature: add gatus dashboard`  | `feature: Add Gatus dashboard`  |
| Imperative mood             | `fix: remove broken redirect`   | `fix: removed broken redirect`  |
| No trailing period          | `docs: update architecture diagram` | `docs: update architecture diagram.` |
| One blank line before body  | description → blank line → body | body directly after description |
| `BREAKING CHANGE` uppercase | `BREAKING CHANGE:`              | `breaking change:`              |
| Single responsibility       | one concern per commit          | mixing feature + refactor + fix |

Each commit must leave the repo in a state where `kustomize build` succeeds on all three overlays.

---

## Recipe: Writing a Commit Message

### 1. Check atomicity

Describe the change in one sentence without "and". If you cannot, split the commit.
Use `git add -p` to stage individual hunks when concerns are mixed in the working tree.

| Signal                                                      | Action                  |
| ----------------------------------------------------------- | ----------------------- |
| Subject needs "and"                                         | Two commits             |
| Two types apply (e.g. `fix` + `refactor`)                   | Two commits             |
| Multiple independent artifacts, even of the same type       | One commit per artifact |
| WIP commits in the branch                                   | Squash before pushing   |

**Same type ≠ same commit.** Adding three skills, three renovate rules, or three unrelated
manifests in a single `chore` commit is still three concerns. Each independently reviewable
or deployable unit gets its own commit.

### 2. Write the subject

`type[(scope)]: description`

The subject is the heading. It must stand alone and be self-sufficient.

**Imperative mood test** — the subject must complete this naturally:

> "If applied, this commit will **[your subject]**."

```
✓ fix traefik middleware order for jellyfin
✗ fixed traefik middleware order for jellyfin   ← past tense, fails the test
```

Good verbs by type:

| Type       | Verbs                                                   |
| ---------- | ------------------------------------------------------- |
| `feature`  | add, introduce, expose, enable, support                 |
| `fix`      | fix, resolve, prevent, correct, handle                  |
| `refactor` | extract, move, rename, simplify, restructure, split     |
| `docs`     | document, update, correct, clarify                      |
| `style`    | format, reformat, align                                 |
| `build`    | upgrade, bump, migrate, add, remove                     |
| `ci`       | configure, update, add, fix                             |
| `chore`    | update, remove, replace, clean up                       |

### 3. Add a body only when needed

The diff shows **what** changed. The body explains **why** — the motivation, the constraint,
the non-obvious decision. Skip it when the subject is self-evident.

**The body is one sentence.** No bullet lists, no multi-line explanations.

```
✓ Default chunks-cache of 8GiB exceeded node memory under light load.
✗ Changed the chunks-cache memory because the default was too high
  and caused OOM kills on the loki pod when running alongside other
  workloads, especially during backup windows.   ← too long
```

One blank line separates the subject from the body.

### 4. Add footers sparingly

Footers come after a blank line following the body. Use them only for:

```
BREAKING CHANGE: …       ← required for changes that need manual intervention
```

Never add AI attribution or tool metadata.

### Anti-patterns

| Anti-pattern                                 | Problem                                       |
| -------------------------------------------- | --------------------------------------------- |
| `fix stuff`, `update`, `changes`, `WIP`      | No information — useless history              |
| `fix: fixed the bug` — past tense            | Fails the imperative mood test                |
| `feat: Add login` — wrong type, capitalized  | Use `feature`; description must be lowercase  |
| Subject contains "and"                       | Multi-concern commit — split it               |
| Body restates the diff                       | Noise — the reader has `git show`             |
| `Co-Authored-By: Claude …`                   | **Forbidden** — see Hard Constraints          |
| Body longer than one sentence                | Keep it tight; one sentence only              |

---

## Examples

Minimal — subject only:

```
docs: correct spelling in README
```

With scope:

```
feature(apps): add audiobookshelf
```

With body (one sentence, explains why):

```
fix(loki): reduce chunks-cache allocated memory to 1 GiB

Default 8 GiB exceeded node memory alongside the promtail daemonset.
```

Renovate-style bump:

```
chore(deps): update loki helm chart to 6.56.0
```

Breaking change:

```
refactor(cnpg)!: migrate postgres storage to local-path
```

With body and breaking change:

```
refactor(cnpg)!: migrate postgres storage to local-path

StorageClass nfs-client could not satisfy CNPG's fsync guarantees.

BREAKING CHANGE: requires manual PVC re-creation and WAL restore from R2.
```
