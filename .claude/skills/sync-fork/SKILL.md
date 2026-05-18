---
name: sync-fork
description: "Safely sync this Tabby fork from the upstream repository. Use when the user asks to update, sync, or refresh this fork from the main upstream repo, especially phrases like \"sync fork\", \"从主仓同步\", \"更新 fork\", \"pull upstream\", or \"bring my fork up to date\"."
---

# Sync Fork

## Overview

Use this skill to update the fork's base branch from the canonical Tabby upstream while protecting local work. In this repository, the expected remotes are:

- `origin`: `https://github.com/MorseWayne/tabby.git`
- `upstream`: `https://github.com/Eugeny/tabby.git`

Prefer a fast-forward sync. Stop and report before any operation that rewrites history, discards local changes, force-pushes, or resolves non-trivial conflicts.

## Safety Rules

- Start by checking the worktree. If `git status --short` is not clean, stop and ask how to handle the existing changes.
- Never run `git reset --hard`, `git clean`, or `git push --force` for this workflow unless the user explicitly requests that exact destructive operation.
- Do not sync from a feature branch by accident. Sync the fork's base branch, normally `master` for this repo.
- Treat `upstream` as read-only. Push only to `origin`.
- If the fork has commits that upstream does not have, stop and summarize options instead of silently rebasing or overwriting them.
- If a conflict requires product, behavior, dependency, or intent judgment, stop and ask for human decision instead of guessing.
- If a sync changes source files substantially, run `npx gitnexus status` afterward; if GitNexus reports staleness, run `npx gitnexus analyze`.

## Workflow

### 1. Inspect State

Run:

```bash
git status --short --branch
git remote -v
git branch --show-current
```

Confirm:

- the worktree is clean
- `origin` points at the fork
- `upstream` points at `Eugeny/tabby`
- the active branch is the fork base branch or the user has approved switching to it

If `upstream` is missing, add it:

```bash
git remote add upstream https://github.com/Eugeny/tabby.git
```

If the remote names are reversed or surprising, stop and ask before changing them.

### 2. Determine Base Branch

Prefer the current branch when it tracks `origin/<branch>` and is clearly the fork base branch.

For this repository, use `master` unless local evidence proves the default branch has changed. To confirm upstream's default branch:

```bash
git remote set-head upstream --auto
git symbolic-ref --short refs/remotes/upstream/HEAD
```

If the command reports `upstream/master`, sync `master`. If it reports another branch, tell the user and sync that branch only after confirming it also matches the fork's intended base branch.

### 3. Fetch Both Remotes

Run:

```bash
git fetch upstream --prune --tags
git fetch origin --prune
```

Then inspect divergence:

```bash
git rev-list --left-right --count HEAD...origin/master
git rev-list --left-right --count HEAD...upstream/master
git rev-list --left-right --count origin/master...upstream/master
```

Replace `master` with the confirmed base branch when needed. Interpret the output as `<left-only> <right-only>`.

If `HEAD...origin/master` shows the local branch is only behind `origin/master`, fast-forward local first:

```bash
git merge --ff-only origin/master
```

If the local branch is ahead of or diverged from `origin/master`, stop and ask before syncing.

### 4. Fast-Forward Local Branch

Only proceed automatically when both the local branch and `origin/<branch>` have no commits that are absent from upstream:

```bash
git merge-base --is-ancestor HEAD upstream/master
git merge-base --is-ancestor origin/master upstream/master
git merge --ff-only upstream/master
```

If fast-forward fails, stop and report:

- current branch
- local-vs-origin commit counts
- local-only commit count
- upstream-only commit count
- whether conflicts are expected
- recommended next step: rebase local fork commits, merge upstream, or create a backup branch before a reset-style repair

Do not choose among those options without user approval.

## Conflict Decision Boundary

Only resolve conflicts automatically when the resolution is mechanical and low-risk, such as accepting an upstream-only fast-forward after prior approval or updating generated metadata that has one obvious valid result.

Ask for human intervention when any conflict is ambiguous, including:

- both sides changed the same behavior, API contract, dependency version, build setting, migration, lockfile, or generated artifact in ways that are not obviously equivalent
- the correct result depends on project intent, product behavior, compatibility, release timing, or whether local fork changes should be preserved
- tests, type checks, or local inspection do not clearly prove one resolution is correct
- resolving the conflict would require deleting local commits, dropping local changes, force-pushing, or rewriting branch history

When escalating to a human, leave the repository in a safe state and report:

- conflicted files
- the branch and command that produced the conflict
- upstream-only and fork-only commit counts
- the specific decision needed for each ambiguous area
- recommended options with trade-offs, without applying one

If a merge or rebase is already in progress and the user has not approved a resolution, do not continue. Ask whether to abort the operation, inspect more context, or wait for a manual edit.

### 5. Push Fork Branch

After a successful fast-forward, push the fork branch:

```bash
git push origin master
```

Do not push tags unless the user specifically asks for tag syncing. If tag syncing is requested, confirm first, then use:

```bash
git push origin --tags
```

### 6. Verify Result

Run:

```bash
git status --short --branch
git log --oneline --decorate --max-count=5
git rev-list --left-right --count origin/master...upstream/master
```

Report:

- synced branch
- old and new HEAD commits when available
- whether `origin/<branch>` now matches `upstream/<branch>`
- any remaining divergence or skipped steps

If source files changed because of the sync, check GitNexus:

```bash
npx gitnexus status
```

Run `npx gitnexus analyze` if the index is stale or if GitNexus instructs you to refresh it.

## Non-Fast-Forward Cases

When the fork contains local commits, present these options and wait:

- **Rebase fork commits onto upstream**: preserves local work with linear history; may require conflict resolution.
- **Merge upstream into fork**: preserves history without rewriting commits; may create a merge commit.
- **Backup then reset-style repair**: create a backup branch first; only use if the user explicitly wants the fork base branch to exactly match upstream.

If rebase or merge conflicts occur, follow **Conflict Decision Boundary**. Do not resolve ambiguous conflicts without human input.

Before any reset-style repair, create a backup branch:

```bash
git branch sync-fork-backup/$(date +%Y%m%d-%H%M%S)
```

Still do not run destructive commands until the user explicitly approves the exact operation.
