# Herdr Worktrees panel — design

Date: 2026-11-24

## Intent

The Merge requests panel (`my-prs`) opens every MR or PR in its own git worktree
under `~/.herdr/worktrees/<repo>/<branch>`. Nothing ever removes them, so they
pile up. A new side panel lists the worktrees of the focused repo and deletes the
ones that are no longer needed, so the clean-up happens where the worktrees were
made instead of by hand in a shell.

The deciding fact for "no longer needed" is whether the branch was merged — and
that is exactly what plain git gets wrong here: GitLab and GitHub squash- or
rebase-merge, which puts new commits on `main`, so `git branch --merged` and
`git branch -d` do not see those branches as merged.

## Goals

- A "Worktrees" panel, opened from a button in the tabs bar like PRs/MRs, Just
  and Docker.
- It lists every worktree of the repo the focused terminal is in.
- The worktree the focused terminal is in is highlighted and cannot be deleted.
- Each row shows whether its branch is merged, so the unneeded ones are visible
  before anything is clicked.
- Delete removes the worktree, closes the Herdr space open on it, and deletes the
  local branch when — and only when — it is merged. When the branch is kept, the
  panel says why.

## Non-goals

- Remote branches are never deleted. Only the local worktree folder and the local
  branch.
- No creating worktrees from this panel. `my-prs` does that.
- No batch "delete all merged" action.

## Anti-goals

- Losing work silently. Uncommitted changes, unpushed commits and a running
  terminal are only ever lost after a confirmation that names them.
- Deleting a branch because a heuristic guessed it was merged when it had local
  commits the merge did not contain.

## Decided with the user

- **Every delete asks first**, also for a clean worktree. Click the delete
  button → the row turns into a confirmation that lists what will happen, with
  `Delete` and `Cancel`.
- **Uncommitted or untracked changes**: the confirmation says so, and confirming
  runs `git worktree remove --force`. Without changes it is a plain
  `git worktree remove`.
- **Open space**: a Herdr space showing that worktree is closed
  (`space.close {id}`) once git has removed the worktree, so a removal git
  refuses leaves its terminals running. The confirmation names it.
- **Local branch**: deleted only if merged. Otherwise kept, and the panel shows
  the reason.
- **Merged check — forge first, then git** (approach 1 below).
- **Merge badge on every row**, refreshed with the list.

## Approaches considered

1. **Forge, then git — chosen.** For a GitLab or GitHub repo (the shared
   `my.repo` the tabs mod already publishes), ask `glab` / `gh` for the MR/PR whose
   source branch is the worktree's branch. Merged = its state is merged **and**
   the local branch tip is an ancestor of (or equal to) the MR's last head commit,
   so no local commit came after what was merged. Outside GitLab/GitHub, or when
   the forge has no MR for the branch, fall back to the git check of approach 2.
   Handles squash merges reliably; costs one forge request per refresh.
2. **Git only, with squash detection.** After a fetch, merged = the branch is an
   ancestor of `origin/<default>`, or its combined diff is already there: build a
   throw-away commit of the branch's tree on top of its merge base
   (`git commit-tree <branch>^{tree} -p $(git merge-base origin/<default> <branch>)`)
   and `git cherry origin/<default> <that>` reports it as `-`. Offline and
   host-independent, but misses merges where conflicts were resolved or the MR
   got extra changes at merge time. Kept as the fallback.
3. **Ancestry only** (what `git branch --merged` does). Rejected: it is the
   behaviour that misses squash merges today.

## What the user sees

```
┌ Worktrees  4 ─────────────────────────── ↻ ┐
│ ▌main                         main         │  ← main checkout, no delete
│ ▌~/dev/dotenv                              │
│ ┃feat/worktrees-panel   Current            │  ← highlighted, no delete
│ ┃~/.herdr/worktrees/dotenv/feat-worktrees… │
│  fix/ssh-config      Merged  space      🗑 │
│  ~/.herdr/worktrees/dotenv/fix-ssh-config  │
│  feat/herdr-just     MR !12 open        🗑 │
│  ~/.herdr/worktrees/dotenv/feat-herdr-just │
└────────────────────────────────────────────┘
```

After 🗑 on `fix/ssh-config`:

```
│  fix/ssh-config      Merged  space         │
│  Delete this worktree?                     │
│   · closes space "fix-ssh-config"          │
│   · 3 uncommitted changes will be lost     │
│   · branch is merged and will be deleted   │
│                         [Cancel] [Delete]  │
```

Badge values: `Merged`, `MR !12 open` / `PR #12 open`, `MR !12 closed`,
`Merged, +2 local commits`, `Merged, local differs`, `No commits`,
`Default branch`, `Not merged`, `Checking…`; none for the main checkout and for
a detached worktree.

`No commits`: the branch points at a commit of main's own line (created there,
or `git reset --hard origin/main`), so it has nothing of its own. Being an
ancestor of main does not make such a branch merged, and it is kept on delete
with "it has no commits of its own". A fast-forward merge also leaves the branch
on main's line: it counts as merged only when its MR or PR says so.

Reasons shown when a branch is kept after delete (in the panel, like the other
panels' error line, and as a `notify`): "MR !12 is still open", "2 commits are not
in origin/main", "no MR found and 2 commits are not in origin/main",
"MR !12 was closed and 2 commits are not in origin/main",
"merged, but 2 local commits came after it",
"merged, but the local branch differs from what was merged",
"no origin/main or origin/master to compare with".

## Behaviour

- **Which repo**: the one containing the focused terminal's folder, on that
  terminal's machine — the same `location()` the tabs mod uses.
- **List**: `git worktree list --porcelain`, main checkout first, then the rest
  by branch name. Each row: branch (or `detached <short sha>`), path with `$HOME`
  shown as `~`, chips for `Main`, `Current`, open `space`, `N changes`
  (uncommitted and untracked files, one `git status` per worktree per refresh,
  run side by side), and the merge badge.
- **Current**: the deepest worktree containing the focused terminal's folder
  (a linked worktree can sit inside the main one — same rule as `spaceOf` in
  `my-prs/worktree.js`). Highlighted, no delete button.
- **Main checkout**: shown, no delete button (git refuses to remove it anyway).
- **Click on a row** (outside its buttons) selects the space showing that
  worktree, or opens a new one on it — the same as a click on an MR row.
- **Refresh**: when the panel first renders a repo, when the repo changes, after
  each delete, on ↻, and every 120 s like the MR panel. The merge badges come
  from one forge request for all branches per refresh, never one per branch.
- **Delete, step by step**: look at the worktree again (changes, HEAD, commits on
  no branch, open space, other terminals in it, whether it became the current
  one). Anything the confirmation did not mention — more changes, a new commit,
  another space or terminal — shows the confirmation again, headed "It changed
  since", with the merge state worked out again for the new HEAD; it is never
  acted on silently. The current worktree is refused. Otherwise remove the
  worktree (`--force` only if the confirmation said changes would be lost); only
  after git removed it, close its space; then, if merged, `git branch -D <branch>`
  (`-D`, because `-d` refuses a squash-merged branch); refresh.
- **No delete button** on the main checkout, the current worktree and a locked
  worktree (git refuses a locked one even with `--force`).
- **Default branch**: a linked worktree on the default branch shows
  `Default branch` and its branch is never deleted.
- **Confirmation lines**, those that apply: `closes space "<name>"`,
  `N other terminals are in it and will be left in a deleted folder`,
  `N uncommitted changes will be lost`, `N commits on no branch will be lost`,
  `the folder is already gone`, `detached, there is no branch to delete`,
  `branch is merged and will be deleted`, `branch is kept: <reason>`.
- **Failures**: git's own message, in the panel's error line, like `my-docker`.

## Constraints

- Herdr mods in `herdr/mods/`, symlinked by `common/herdr.sh`. SVG icons are not
  drawn through those links, so the panel button's icon lives in
  `herdr/patches/my-tabs/`.
- `my-tabs` and `my-layout` are rebuilt by `common/herdr.sh` from what Herdr
  ships plus `herdr/patches/`; never edit the installed clones by hand.
- `glab` / `gh` may only be reachable through `mise` — reuse the `runTool`
  fallback from `my-prs/main.js`.
- Hosts and logins come from glab's and gh's own config, never from this repo.
- Commands run on the focused terminal's machine (`exec(…, { on })`).
- No `void` operator; floating promises get `.catch(...)`.

## Parts

- `herdr/mods/my-worktrees/mod.json` — `{ "place": "none", "title": "Worktrees" }`.
- `herdr/mods/my-worktrees/main.js` — the panel.
- `herdr/mods/my-worktrees/git.js` — worktree parsing, current worktree, the
  merge check; imports nothing from Herdr, so it runs under `node --test`.
- `herdr/mods/my-worktrees/forge.js` — the one GraphQL request for all
  branches; also Herdr-free.
- `herdr/mods/my-worktrees/spaces.js` — which space shows a worktree, opening one.
- `herdr/patches/my-tabs/git-space.js` — like `just-space.js`: is the focused
  folder in a git repo; publishes shared `my.git` (`{ root, on }` or null).
- `herdr/patches/my-tabs/worktree.svg` — panel button icon.
- `herdr/patches/my-tabs/button.js` — a `Worktrees` button when `my.git` is set.
- `herdr/patches/my-tabs/render-start.js` — hide the panel when the focused
  folder is not in a git repo and the Worktrees panel is the active one.
- `common/herdr.sh` — import `git-space.js`, copy it and the icon, add
  `"worktrees"` to the panels list, add the `my-worktrees` block to the layout.

## Left to the builder

- Whether `my-worktrees` can import `checkouts` / `spaceOf` / opening from
  `../my-prs/worktree.js` (check with `herdr-app check`); if Herdr does not
  resolve imports across mod folders, give `my-worktrees` its own copy.
- The exact forge queries, as long as each is one request for all branches:
  GitLab GraphQL `project.mergeRequests(sourceBranches: […])` with `state`,
  `iid`, `sourceBranch`, `diffHeadSha`; GitHub GraphQL with one aliased
  `pullRequests(headRefName: …, first: 1, orderBy: UPDATED_AT desc)` per branch.
  When a branch has several MRs, the most recently updated one counts.
- The default branch for the git fallback: `origin/HEAD`, else `main`, else
  `master`. How often to `git fetch` it (at most once per refresh).
- How a prunable worktree (folder already gone) is shown and removed
  (`git worktree prune` is the natural fit).
- Exact colours: reuse the theme tokens the other panels use (`t.accent` for
  Current, `t.ansi2` / `t.blocked` / `t.ansi1` / `t.dim` for the badges).
