# Merging Upstream OpenClaw Updates Into This Fork

This repo is a personal fork. The workflow is:

- `upstream` tracks the original OpenClaw repo (`openclaw/openclaw`).
- `origin` tracks your fork (where you push).

## One-time Setup

Check remotes:

```bash
git remote -v
```

Recommended remote layout:

- `origin`: your fork (push here)
- `upstream`: OpenClaw upstream (pull from here)

If your remotes are not set up yet:

```bash
git remote rename origin upstream
git remote add origin git@github.com:<you>/<your-fork>.git
```

Point `upstream` at OpenClaw and disable upstream pushes:

```bash
git remote set-url upstream https://github.com/openclaw/openclaw.git
git remote set-url --push upstream DISABLE
```

If your `origin` SSH URL is wrong, fix it (common mistake: missing the `:`):

```bash
git remote set-url origin git@github.com:<you>/<your-fork>.git
```

If you use GitHub CLI, you can also set the canonical SSH URL like this:

```bash
git remote set-url origin "$(gh repo view <you>/<your-fork> --json sshUrl -q .sshUrl)"
```

## Update Your Fork From Upstream (When You Want)

This updates your local `main` from upstream, then pushes the result to your fork:

```bash
git fetch upstream --prune
git switch main
git merge upstream/main
git push origin main
```

If you prefer a linear history instead of a merge commit:

```bash
git fetch upstream --prune
git switch main
git rebase upstream/main
git push origin main
```

If upstream uses a different default branch (e.g. `master`), replace `upstream/main` accordingly.

## When A Merge Conflict Happens

1) See what is conflicted:

```bash
git status
git diff --name-only --diff-filter=U
```

2) Edit the conflicted files, remove conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`), and keep the intended combined result.

3) Mark each resolved file:

```bash
git add <file>
```

4) Finish the merge:

```bash
git commit
```

5) Push to your fork:

```bash
git push origin main
```
