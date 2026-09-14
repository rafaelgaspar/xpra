---
name: rafaelgaspar-fork
description: >-
  Work with the rafaelgaspar/xpra fork of Xpra-org/xpra — stacked feat branches,
  rafaelgaspar integration pointer, release tagging, upstream tag rebuilds.
  Use when changing Xpra upstream-bound code, fork branches, stack order,
  or rafaelgaspar/xpra release tags consumed by k3s-home desktop-base.
disable-model-invocation: true
---

# Xpra fork (`rafaelgaspar/xpra`)

Upstream: [Xpra-org/xpra](https://github.com/Xpra-org/xpra). Fork:
[rafaelgaspar/xpra](https://github.com/rafaelgaspar/xpra). Ships
**integration tags** from branch **`rafaelgaspar`** (format `vX.Y.Z-rafaelgaspar.N`, starting at `.0`).

This skill covers **this repository only** — branch workflow, CI, and integration replay.
k3s-home desktop-base consumes forked Python sources as an overlay on top of xpra.org
Debian packages (see `images/desktop-base/Dockerfile`).

## Repos and branches

| Branch         | Role                                                                                  |
| -------------- | ------------------------------------------------------------------------------------- |
| `master`       | Upstream mirror only — auto-sync, no features                                         |
| `feat/<name>`  | One feature; branch from the **current stack tip** (or `feat/rafaelgaspar` for infra) |
| `rafaelgaspar` | Points at the stack tip — **only this branch ships** (default branch)                 |

**Invariant:** `feat/rafaelgaspar` is always the stack root (infra: release tagging,
tag-bump automation, agent skill, fork README).

## Stacked feat branches (git is the source of truth)

Features form a **linear stack**:

```text
vX.Y.Z (upstream tag)
 └── feat/rafaelgaspar
      └── feat/<next>
           └── feat/<tip>  ← rafaelgaspar reset --hard here
```

Order is defined by **git merge-base**, not a manifest file:

- `feat/rafaelgaspar` must be based on the upstream release tag.
- Every other `feat/*` must be based on exactly one parent **feat branch tip**.
- The stack must be **linear** (one child per parent).
- `rafaelgaspar` must match the stack tip commit.

Inspect the stack:

```sh
git log --oneline --graph --decorate feat/rafaelgaspar feat/<...> rafaelgaspar
```

Validate without changing anything:

```sh
./.github/scripts/rebuild-rafaelgaspar.sh --dry-run vX.Y.Z
```

## Adding an Xpra feature

1. Branch from the **current stack tip** (not directly from the upstream tag):

   ```sh
   git fetch origin
   git checkout -B feat/<name> origin/<stack-tip>
   ```

2. Implement as normal commits on `feat/<name>`.
3. Publish integration:

   ```sh
   git checkout rafaelgaspar
   git reset --hard feat/<name>
   git push --force-with-lease origin rafaelgaspar
   ```

   Release tagging runs on push to `rafaelgaspar`.

Do **not** commit features to `master` or maintain parallel squash-merge history on
`rafaelgaspar`. Do **not** export patch tarballs — the fork tag is the artifact.

## Upstream tag bump (automation / manual replay)

When upstream releases tag **T**, `.github/workflows/rafaelgaspar-tag-bump.yaml` runs
`.github/scripts/rebuild-rafaelgaspar.sh`:

1. Discover the linear stack from git merge-base relationships.
2. Validate `feat/rafaelgaspar` is based on **T** (after rebase) and `rafaelgaspar` matches the tip.
3. Rebase `feat/rafaelgaspar` onto **T**, then each next feat onto its parent tip.
4. `git checkout rafaelgaspar && git reset --hard <stack-tip>`.
5. Push rebased feat branches and `rafaelgaspar` with `--force-with-lease`.

Manual replay:

```sh
./.github/scripts/rebuild-rafaelgaspar.sh --push vX.Y.Z
```

Optional `--squash` collapses each feat layer to one commit during rebuild (see below).

Scheduled tag-bump skips when the newest upstream semver tag merged into
`feat/rafaelgaspar` already equals the latest upstream release tag.

## Squash on rebuild?

**Default: do not squash.** Keep normal commit history on feat branches while developing
(bisect, review, incremental CI).

**Optional `--squash` on tag-bump rebuild** collapses each layer to a single commit so
`git log vX.Y.Z..rafaelgaspar` shows one commit per shipped feature. Use this when you
want a clean release-readable integration log without maintaining squash merges by hand.

Do **not** squash during day-to-day feature work — only at rebuild time if you explicitly
pass `--squash` (or enable the workflow_dispatch input).

## Scope

| Belongs on the fork (`feat/*`)                       | Does not belong on this public repo             |
| ---------------------------------------------------- | ----------------------------------------------- |
| App source changes (shared WM, pointer warp, …)      | Deploy secrets, private config repos            |
| CI: release tagging, tag-bump replay                 | References to private infra paths or repo names   |
| Agent skill for fork workflow                        | `PLAN-*.md` planning notes                      |

New upstream-bound work targets **`feat/*` stacked on the tip → `rafaelgaspar` pointer**,
not out-of-tree patch stacks.

## Agent checklist

- [ ] Work on a **`feat/*`** branch stacked on the current tip, not `master` or `rafaelgaspar` directly (except pointer updates).
- [ ] **`feat/rafaelgaspar` remains the stack root** on the upstream release tag.
- [ ] New features branch from the stack tip; never create parallel siblings (linear stack only).
- [ ] Publish with `rafaelgaspar` reset to the new tip, not squash merges.
- [ ] No private deploy repo names, cluster paths, or `PLAN-*.md` in commits here.
