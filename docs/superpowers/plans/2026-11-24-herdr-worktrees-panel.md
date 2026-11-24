# Herdr Worktrees Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Herdr side panel that lists the focused repo's git worktrees, highlights the current one, shows whether each branch is merged, and deletes the unneeded ones.

**Architecture:** A new mod `herdr/mods/my-worktrees` with its decision logic in two files that import nothing from Herdr (`git.js`, `forge.js`), so they run under plain `node --test`. The tabs clone (`herdr/patches/my-tabs`) learns whether the focused folder is in a git repo, publishes it as shared `my.git`, and shows a Worktrees button. `common/herdr.sh` wires the patch and the layout block.

**Tech Stack:** Herdr mod API (`gpui-kit`, `gpui-base`, `herdr`), git, `glab` / `gh` GraphQL, bash + jq for the build script, Node 26 `node:test` for throwaway tests.

**Spec:** `docs/superpowers/specs/2026-11-24-herdr-worktrees-panel-design.md`

## Global Constraints

- Never use the `void` operator. A floating promise gets `.catch(...)` as a plain statement.
- Code, comments and every UI string in English; copy exactly as the spec and this plan give it.
- No commit and no push unless the user asks for that specific change. No `Co-Authored-By` or "Generated with" lines.
- Every `exec` passes `{ on }` (the focused terminal's machine); repo-level git commands run with `cwd: common` (the git common dir from `my.git`), worktree-level ones with `cwd: <worktree path>`.
- Remote branches are never deleted. A local branch is deleted only when `mergeState(...).merged` is true, with `git branch -D`.
- SVG icons live in `herdr/patches/my-tabs/` (Herdr does not draw SVGs through the mod symlinks).
- Never edit the installed `my-tabs` / `my-layout` clones; change `herdr/patches/` and `common/herdr.sh`.
- Tests are throwaway `node:test` files in the session scratchpad (`$SCRATCH` below), never committed: the repo has no test suite, package.json or runner, and gets none.
- Do not run `./common/herdr.sh` or anything that installs into `~/.config/herdr-app` without the user's go-ahead.

`$SCRATCH` = `/tmp/claude-1000/-home-serhii-dev-dotenv/8e0b7478-78aa-46ec-b19c-484a1ac0f648/scratchpad/worktrees`

## Review Focus

- A branch name with `"`, `\` or `/` reaches a GraphQL query: it must be escaped, not break the query. → Task 2, `escapes branch names`.
- The worktree gets new changes after the confirmation was shown without a "changes will be lost" line: the panel asks again instead of forcing. → Task 1, `removeMode`.
- `glab` / `gh` missing, unauthorized or offline: badges still come from git and the error line names the forge problem. → Task 2, `fetchMergeRequests failures`.
- The focused folder only shares a prefix with a worktree path (`/r` vs `/rx`): that worktree is not current. → Task 1, `currentWorktree`.
- A repo with no `origin/main` / `origin/master`: rows say why they are not merged instead of crashing, and a merged MR still counts. → Task 1, `no base`.

## Deviations

- `my-worktrees` has its own copies of `runTool` (from `my-prs/main.js`) and `place` / `spaceOf` (from `my-prs/worktree.js`) instead of importing across mod folders: Herdr's import resolution between mods is unverified and an import change needs a Herdr restart to show.
- Task 1: `mergeState`'s `ctx.forge` is the noun `"MR"` / `"PR"` / `null` instead of a boolean, so a GitHub repo reads "no PR found and …" rather than "no MR found and …". The tests pass `forge: "MR"` / `"PR"` / `null`.
- Task 1: the squash check runs `commit-tree --no-gpg-sign`: with `commit.gpgSign` in the user's config it would otherwise start gpg from inside Herdr. The tests run git with `GIT_CONFIG_GLOBAL=/dev/null` and no identity, which also proves the `-c user.name/user.email` pair is enough.
- Task 2: both query shapes were also run once against the live APIs (`gh api graphql` on this repo, `glab api graphql` on a project that does not exist, so only the schema is checked): no errors.
- Task 4: the background fetch runs `git -c "core.sshCommand=ssh -o BatchMode=yes" fetch`: it repeats every 120 s, and without BatchMode ssh could pop a passphrase or host-key prompt each time. Cost: a custom `core.sshCommand` is not used for that one fetch. `defaultBase` is asked again after the fetch.
- Task 4: when the forge request fails, `mergeState` gets `forge: null`, so a row never says "no MR found" for an MR that was simply not asked about.
- Task 4: prunable rows get a merge state too, so pruning one with a merged branch deletes the branch like any other delete.
- Task 4: the confirmation keeps the merge state it showed, and `Delete` acts on that one, even if a refresh changed the badge in between. A space that opened after the confirmation was shown makes it ask again, like new changes do.
- Task 4: `herdr-app check` warns "a reload stranded script tasks … cx.timer.every"; `my-prs` prints the same warning with the same timer, so it comes from the check's reload, not from this mod.
- Task 3: the layout check was read with the Read tool instead of `jq`; the built `my-layout.json` has the `worktrees` block between `merge-requests` and `just`, and `herdr-app check` passed on the built `my-tabs`.
- Final review (fresh Opus reviewer), fixed:
  - Critical: a branch could be deleted on a stale merge state, losing a commit made after the badge said "Merged". The confirmation and `Delete` now read the worktree's HEAD, work the state out again when it moved, and ask again. `removeMode` became `deleteDecision(shown, now)`, which also asks again for more changes than shown, new commits on no branch, a new space or more terminals, and refuses the current worktree. Test `deleteDecision` RED→GREEN.
  - Important: the current worktree could be deleted when focus moved into it while its confirmation was open. `deleteDecision` returns `refuse`, and the confirmation only renders on a deletable row. Covered by `deleteDecision`.
  - Important: a refresh wiped the delete's error. Delete errors live in their own `actionError`. Checked with `herdr-app check` only (UI state).
  - Important: the space was closed before a removal git refuses (locked, submodules). The space is closed only after git removed the worktree, and locked rows get no delete button. Checked with `herdr-app check` only.
  - Important: commits on a detached worktree were lost silently. New `strayCommits`, and a "N commits on no branch will be lost" line. Test `strayCommits` RED→GREEN.
  - Important: other terminals inside the worktree were not mentioned. New `othersIn` in `spaces.js`, and a "N other terminals are in it and will be left in a deleted folder" line. Checked with `herdr-app check` only.
  - Re-graded Minor → Important: a linked worktree on the default branch showed "Merged" and would get `git branch -D main`. It now shows `Default branch` and its branch is kept. Test `mergeState: default branch` RED→GREEN.
  - Part of a Minor, since it is a data-loss path: `countChanges` passes `--untracked-files=normal --ignore-submodules=none`, so a config that hides untracked files cannot make a dirty worktree look clean. Test `countChanges` RED→GREEN.
  - The `forge.js` header said glab/gh run on the repo's machine; they run on this computer, like `my-prs`. Comment fixed.
- After the live run (user's screenshot): a branch reset to `origin/master` with uncommitted work showed `Merged`, because the git check took "ancestor of origin/main" as merged. A branch whose tip is on main's own first-parent line now shows `No commits` and is kept; only a merge commit, a rebase or squash match, or an MR whose head is the tip counts as merged. The "+N local commits" count also leaves out main's own commits. Test `mergeState: no commits of its own` RED→GREEN. The `rebased` fixture now cherry-picks with `-x`: picked in the same second it produced identical commits, which is a fast-forward, not a rebase merge.
- Added at the user's request after the live run: an `N changes` chip on every row with uncommitted or untracked files, from `countChanges` (already tested) run for all worktrees at once each refresh; a worktree git cannot read counts as 0. Checked with `herdr-app check` only (UI).
- Task 4 Step 5 stays unticked: `herdr-app check` passes and the user ran the panel live (list, `Current`, badges, the `Merged` bug above), but the delete flows were not confirmed live in this session.
- Final: Ruling: whether `space.close` can be deferred by Herdr when processes run is unknown — the worktree is removed first now, so at worst a space stays open on a deleted folder — cost if wrong: a stale space to close by hand.
- Final: minor (deferred): ignored files (`.env`, local config) are deleted by `git worktree remove` without being named in the confirmation.
- Final: minor (deferred): `git worktree prune` prunes every prunable entry, not only the clicked row (e.g. worktrees on an unmounted disk).
- Final: minor (deferred): every rejection of glab/gh reads "is not installed"; a GitLab project that does not exist reads "Unexpected glab output: TypeError…".
- Task 1: tests added beyond the plan — a merged MR whose head is not in the repo (`Merged, local differs`), a closed MR on a squash-merged branch (git still finds it merged), and the `PR` noun.

---

### Task 1: Git logic (`git.js`)

**Files:**
- Create: `herdr/mods/my-worktrees/git.js`
- Test: `$SCRATCH/git.test.mjs` (throwaway)

**Interfaces:**
- Consumes: nothing. `git.js` imports nothing.
- Produces (all exported):
  - `type Git = (args: string[]) => Promise<{ ok: boolean, out: string, err: string }>` (JSDoc typedef; `out`/`err` trimmed)
  - `type Worktree = { path: string, head: string, branch: string | null, main: boolean, prunable: boolean, locked: boolean }`
  - `type MR = { label: string, state: "merged" | "open" | "closed", head: string, url: string }` (label: `"MR !12"` / `"PR #12"`)
  - `type MergeState = { badge: { text: string, kind: "ok" | "warn" | "muted" }, merged: boolean, reason: string | null }`
  - `parseWorktrees(porcelain: string): Worktree[]`
  - `currentWorktree(worktrees: Worktree[], cwd: string | null): string | null` — the path
  - `countChanges(git: Git): Promise<number>`
  - `defaultBase(git: Git): Promise<string | null>` — e.g. `"origin/main"`
  - `mergeState(git: Git, wt: Worktree, mr: MR | undefined, ctx: { base: string | null, forge: "MR" | "PR" | null }): Promise<MergeState>`
  - `removeMode(shownChanges: number, nowChanges: number): "plain" | "force" | "ask"`

- [x] **Step 1: Write the failing tests** in `$SCRATCH/git.test.mjs`. The `Git` for tests wraps `execFileSync("git", args, { cwd })`. A `before` builds a fixture with `child_process`: a bare `origin`, a clone `work` (identity set by `-c user.name=t -c user.email=t`), on `main` one base commit, then branches pushed to origin and merged on `main` four ways: `squashed` (2 commits, `merge --squash`), `rebased` (2 commits, cherry-picked one by one), `merged` (`merge --no-ff`), `open` (2 commits, not merged); `main` pushed and fetched.

```js
test("parseWorktrees", () => {
  const p = "worktree /r\nHEAD a1\nbranch refs/heads/main\n\nworktree /r/.wt/x\nHEAD b2\nbranch refs/heads/feat/x\n\n" +
    "worktree /w/det\nHEAD c3\ndetached\n\nworktree /w/gone\nHEAD d4\nbranch refs/heads/old\nprunable gitdir file points to non-existent location\n\n" +
    "worktree /w/lk\nHEAD e5\nbranch refs/heads/lk\nlocked held\n\n";
  assert.deepEqual(parseWorktrees(p), [
    { path: "/r", head: "a1", branch: "main", main: true, prunable: false, locked: false },
    { path: "/r/.wt/x", head: "b2", branch: "feat/x", main: false, prunable: false, locked: false },
    { path: "/w/det", head: "c3", branch: null, main: false, prunable: false, locked: false },
    { path: "/w/gone", head: "d4", branch: "old", main: false, prunable: true, locked: false },
    { path: "/w/lk", head: "e5", branch: "lk", main: false, prunable: false, locked: true },
  ]);
  assert.deepEqual(parseWorktrees("worktree /r.git\nbare\n\n"), []);
});

test("currentWorktree", () => {
  const wts = parseWorktrees("worktree /r\nHEAD a\nbranch refs/heads/main\n\nworktree /r/.wt/x\nHEAD b\nbranch refs/heads/x\n");
  assert.equal(currentWorktree(wts, "/r/.wt/x/src"), "/r/.wt/x");
  assert.equal(currentWorktree(wts, "/r/src"), "/r");
  assert.equal(currentWorktree(wts, "/r"), "/r");
  assert.equal(currentWorktree(wts, "/rx"), null);
  assert.equal(currentWorktree(wts, null), null);
});

test("removeMode", () => {
  assert.equal(removeMode(0, 0), "plain");
  assert.equal(removeMode(3, 0), "plain");
  assert.equal(removeMode(3, 5), "force");
  assert.equal(removeMode(0, 2), "ask");
});

test("countChanges", async () => { /* untracked file in work → 1; after removing it → 0 */ });

test("defaultBase", async () => {
  assert.equal(await defaultBase(git), "origin/main");          // clone set origin/HEAD
  // after `git remote set-head origin -d`
  assert.equal(await defaultBase(git), "origin/main");
  // in a repo with no remote
  assert.equal(await defaultBase(lone), null);
});

test("mergeState: git fallback", async () => {
  const ctx = { base: "origin/main", forge: false };
  for (const b of ["squashed", "rebased", "merged"])
    assert.deepEqual(await mergeState(git, wt(b), undefined, ctx), { badge: { text: "Merged", kind: "ok" }, merged: true, reason: null });
  assert.deepEqual(await mergeState(git, wt("open"), undefined, ctx),
    { badge: { text: "Not merged", kind: "muted" }, merged: false, reason: "2 commits are not in origin/main" });
  assert.equal((await mergeState(git, wt("open"), undefined, { ...ctx, forge: true })).reason,
    "no MR found and 2 commits are not in origin/main");
});

test("mergeState: forge", async () => {
  const ctx = { base: "origin/main", forge: true };
  const tip = wt("open").head;
  assert.equal((await mergeState(git, wt("open"), { label: "MR !7", state: "merged", head: tip, url: "" }, ctx)).merged, true);
  // MR head = the parent of tip: one local commit came after the merge
  assert.deepEqual(await mergeState(git, wt("open"), { label: "MR !7", state: "merged", head: parentOf(tip), url: "" }, ctx),
    { badge: { text: "Merged, +1 local commit", kind: "warn" }, merged: false, reason: "merged, but 1 local commit came after it" });
  assert.deepEqual(await mergeState(git, wt("open"), { label: "MR !7", state: "open", head: tip, url: "" }, ctx),
    { badge: { text: "MR !7 open", kind: "warn" }, merged: false, reason: "MR !7 is still open" });
  assert.deepEqual(await mergeState(git, wt("open"), { label: "MR !7", state: "closed", head: tip, url: "" }, ctx),
    { badge: { text: "MR !7 closed", kind: "muted" }, merged: false, reason: "MR !7 was closed and 2 commits are not in origin/main" });
});

test("mergeState: no base", async () => {
  const ctx = { base: null, forge: false };
  assert.deepEqual(await mergeState(git, wt("open"), undefined, ctx),
    { badge: { text: "Not merged", kind: "muted" }, merged: false, reason: "no origin/main or origin/master to compare with" });
  const tip = wt("open").head;
  assert.equal((await mergeState(git, wt("open"), { label: "PR #3", state: "merged", head: tip, url: "" }, ctx)).merged, true);
});
```

`wt(b)` builds a `Worktree` for branch `b` with `head` = `git rev-parse b`; `parentOf(sha)` = `git rev-parse sha^`. Counts: `1 commit is` / `1 local commit came` singular, plural otherwise.

- [x] **Step 2: Run** `node --test $SCRATCH/git.test.mjs` — Expected: FAIL, `git.js` not found.

- [x] **Step 3: Implement `git.js`.** `parseWorktrees`: split blocks on `/\n\n+/`, drop empty and `bare` blocks, the first block of the input is `main`. `currentWorktree`: the longest path `p` with `cwd === p || cwd.startsWith(p + "/")`. `countChanges`: lines of `status --porcelain`. `defaultBase`: `symbolic-ref --quiet --short refs/remotes/origin/HEAD`, else the first of `origin/main`, `origin/master` that `rev-parse --verify --quiet` finds. `removeMode`: `now === 0` → plain, `shown > 0` → force, else ask.

`mergeState` order: no `wt.branch` or `wt.main` is not passed in (caller skips them). Merged MR: `tip === mr.head` or `merge-base --is-ancestor tip mr.head` → merged; else if `cat-file -e mr.head^{commit}` → `+N` with `rev-list --count mr.head..tip`; else fall back to git and, if git says not merged, badge `Merged, local differs` (warn), reason `merged, but the local branch differs from what was merged`. Open MR → open result, no git check. Closed or no MR → git check. The git check, against `base`:

```text
1. merge-base --is-ancestor <tip> <base>                  → merged
2. cherry <base> <tip>: lines non-empty and all "-"       → merged (rebase merge)
3. mb   = merge-base <base> <tip>
   tmp  = -c user.name=squash-check -c user.email=squash-check
          commit-tree <tip>^{tree} -p <mb> -m squash-check
   cherry <base> <tmp> starts with "-"                     → merged (squash merge)
4. otherwise not merged; N = count of "+" lines from step 2
```

- [x] **Step 4: Run** `node --test $SCRATCH/git.test.mjs` — Expected: all pass.

### Task 2: Forge queries (`forge.js`)

**Files:**
- Create: `herdr/mods/my-worktrees/forge.js`
- Test: `$SCRATCH/forge.test.mjs` (throwaway)

**Interfaces:**
- Consumes: the `MR` shape from Task 1.
- Produces:
  - `type Forge = { forge: "gitlab" | "github", host: string | null, path: string }` (what `repo-space.js` already parses)
  - `type Run = (tool: string, args: string[]) => Promise<{ code: number, stdout: string, stderr: string }>` (rejects when the tool is missing)
  - `fetchMergeRequests(run: Run, forge: Forge, branches: string[]): Promise<{ mrs: Map<string, MR>, error: string | null }>`
  - exported for tests only: `gitlabQuery(path, branches)`, `githubQuery(owner, name, branches)`, `parseGitlab(json)`, `parseGithub(json, branches)`

Query shapes (strings built with `JSON.stringify` for every value):

```graphql
query { project(fullPath: "<path>") { mergeRequests(sourceBranches: [<branches>], sort: UPDATED_DESC, first: 100) {
  nodes { iid state sourceBranch diffHeadSha webUrl } } } }

query { repository(owner: "<owner>", name: "<name>") {
  b0: pullRequests(headRefName: "<branch 0>", first: 1, orderBy: {field: UPDATED_AT, direction: DESC}) { nodes { number state headRefOid url } }
  b1: … } }
```

- [x] **Step 1: Write the failing tests**

```js
test("escapes branch names", () => {
  assert.ok(gitlabQuery("g/s/r", ["feat/a", 'we"i\\rd']).includes('sourceBranches: ["feat/a","we\\"i\\\\rd"]'));
  assert.ok(githubQuery("o", "r", ["a", 'q"']).includes('b1: pullRequests(headRefName: "q\\""'));
});

test("parseGitlab", () => {
  const json = { data: { project: { mergeRequests: { nodes: [
    { iid: "9", state: "opened", sourceBranch: "a", diffHeadSha: "s9", webUrl: "u9" },
    { iid: "4", state: "merged", sourceBranch: "a", diffHeadSha: "s4", webUrl: "u4" },
    { iid: "5", state: "locked", sourceBranch: "b", diffHeadSha: "s5", webUrl: "u5" },
  ] } } } };
  const mrs = parseGitlab(json);
  assert.deepEqual(mrs.get("a"), { label: "MR !9", state: "open", head: "s9", url: "u9" }); // most recent wins
  assert.equal(mrs.get("b").state, "open");
});

test("parseGithub", () => {
  const json = { data: { repository: { b0: { nodes: [{ number: 3, state: "MERGED", headRefOid: "h3", url: "u3" }] }, b1: { nodes: [] } } } };
  const mrs = parseGithub(json, ["a", "b"]);
  assert.deepEqual(mrs.get("a"), { label: "PR #3", state: "merged", head: "h3", url: "u3" });
  assert.equal(mrs.has("b"), false);
});

test("fetchMergeRequests args", async () => {
  const calls = [];
  const run = async (tool, args) => { calls.push([tool, args]); return { code: 0, stdout: '{"data":{"project":{"mergeRequests":{"nodes":[]}}}}', stderr: "" }; };
  await fetchMergeRequests(run, { forge: "gitlab", host: "gitlab.example.com", path: "g/r" }, ["a"]);
  assert.deepEqual(calls[0].slice(0, 1), ["glab"]);
  assert.deepEqual(calls[0][1].slice(0, 5), ["api", "graphql", "--hostname", "gitlab.example.com", "-f"]);
  assert.ok(calls[0][1][5].startsWith("query="));
  calls.length = 0;
  await fetchMergeRequests(run, { forge: "github", host: null, path: "o/r" }, []);
  assert.equal(calls.length, 0); // no branches, no request
});

test("fetchMergeRequests failures", async () => {
  const f = { forge: "github", host: null, path: "o/r" };
  assert.deepEqual(await fetchMergeRequests(async () => { throw new Error("x"); }, f, ["a"]), { mrs: new Map(), error: "gh is not installed" });
  assert.deepEqual(await fetchMergeRequests(async () => ({ code: 1, stdout: "", stderr: "HTTP 401: Unauthorized" }), f, ["a"]), { mrs: new Map(), error: "gh: not authorized" });
  assert.deepEqual(await fetchMergeRequests(async () => ({ code: 1, stdout: "", stderr: "dial tcp: timeout" }), f, ["a"]), { mrs: new Map(), error: "gh: dial tcp: timeout" });
  assert.equal((await fetchMergeRequests(async () => ({ code: 0, stdout: "nope", stderr: "" }), f, ["a"])).error.startsWith("Unexpected gh output"), true);
});
```

- [x] **Step 2: Run** `node --test $SCRATCH/forge.test.mjs` — Expected: FAIL, `forge.js` not found.
- [x] **Step 3: Implement `forge.js`.** Tool is `glab` for gitlab, `gh` for github; args `["api", "graphql", ...(host ? ["--hostname", host] : []), "-f", "query=" + query]`. GitHub `path` splits at the first `/` into owner and name. State map: GitLab `opened`/`locked` → open, `merged`, `closed`; GitHub `OPEN`/`MERGED`/`CLOSED` lowercased.
- [x] **Step 4: Run** `node --test $SCRATCH/forge.test.mjs` — Expected: all pass.

### Task 3: Tabs patch and build wiring

**Files:**
- Create: `herdr/patches/my-tabs/git-space.js`, `herdr/patches/my-tabs/worktree.svg`
- Modify: `herdr/patches/my-tabs/render-start.js`, `herdr/patches/my-tabs/button.js`, `common/herdr.sh` (`assemble_my_tabs`, `assemble_my_layout` and its comment)

**Interfaces:**
- Consumes: `location()` and the `repoSpace(cx)` result from `repo-space.js`.
- Produces: shared `"my.git"` = `{ common: string, on: string | null, forge: Forge | null }` (Task 2's `Forge`); `gitSpace(cx, repo): { common, on } | null | undefined` in `git-space.js`; panel id `"worktrees"`; layout block `{ id: "worktrees", type: "block", content: { mod: "my-worktrees" } }`.

- [x] **Step 1: Write `git-space.js`** in the shape of `just-space.js`: answers keyed by `[cwd, on]`, one `exec("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, on })` per key, `null` when it fails, forgotten on a rejected exec. It publishes `my.git` only once `repo !== undefined`, with `forge: repo || null`, and only when the JSON changed.
- [x] **Step 2: Wire it.** `render-start.js`: after the `repoSpace`/`justSpace` line add `const git = gitSpace(cx, repo);` and hide the panel when `git === null` and `body?.active === "worktrees"`, like the other two. `button.js`: right after the MRs button, `.when(Boolean(git), el => el.child(panelButton("worktrees", "Worktrees", "mods/my-tabs/worktree.svg")))`. `worktree.svg`: a 24×24 `stroke="currentColor"` git-fork glyph in the style of `merge-request.svg`.
- [x] **Step 3: Wire `common/herdr.sh`.** Add `printf 'import { gitSpace } from "./git-space.js";\n'`, the panels list becomes `[...(&), "merge-requests", "worktrees", "just", "docker"]`, copy `worktree.svg` and `git-space.js` with the other patch files, add the layout block after `merge-requests`, and name `my-worktrees` in the `assemble_my_layout` comment.
- [x] **Step 4: Verify.** `bash -n common/herdr.sh` → no output. With the user's go-ahead (it reads the installed Herdr under `~/.config/herdr-app`, writes only to `$SCRATCH`): `bash -c 'source common/herdr.sh; assemble_my_tabs "$1/my-tabs" test && assemble_my_layout "$1/my-layout.json" test && herdr-app check "$1/my-tabs"' _ $SCRATCH/build` → check passes, and `jq '[.. | objects | select(.id? == "worktrees")] | length' $SCRATCH/build/my-layout.json` → `1`.

### Task 4: The panel (`my-worktrees`)

**Files:**
- Create: `herdr/mods/my-worktrees/mod.json` (`{ "place": "none", "title": "Worktrees" }`), `herdr/mods/my-worktrees/spaces.js`, `herdr/mods/my-worktrees/main.js`

**Interfaces:**
- Consumes: Task 1 exports, `fetchMergeRequests` (Task 2), shared `my.git` (Task 3).
- Produces: `spaces.js` exports `spaceOf(path: string, all: Worktree[], on: string | null): SpaceInfo | undefined` (copy of `place` + `spaceOf` from `my-prs/worktree.js`) and `openSpace(path, all, on): void` (`space.select` the found one, else `space.new { folder: path, machine: on }`).

- [x] **Step 1: Refresh.** `main.js`, a `View` in the shape of `my-prs`: re-key on `JSON.stringify(shared("my.git"))`, a request counter, `cx.timer.every(120000, …)`, ↻ in the header. One refresh: `parseWorktrees` → rows shown at once with `Checking…` badges → `defaultBase` → best-effort `git fetch --quiet origin <base without "origin/">` with `timeout: 30000`, errors ignored → `fetchMergeRequests(runTool, forge, branches)` when `forge` is set → `mergeState` for every row that has a branch and is not `main` or `prunable`. A forge error goes to the error line; badges still show. `$HOME` of the machine (`sh -c 'printf %s "$HOME"'` with `{ on }`) is shown as `~` in paths.
- [x] **Step 2: Rows.** Title: branch, else `detached <first 7 of head>`. Chips: `Main`, `Current` (accent, plus an accent border on the row), `space` when `spaceOf` finds one, `Missing` for prunable, `Locked` for locked, and the badge coloured `ok` → `t.ansi2`, `warn` → `t.blocked`, `muted` → `t.dim`. Second line: the path. A click on the title or path calls `openSpace` (not for prunable). A `delete` text button, styled like `my-docker`'s `remove`, on every row except `Main` and `Current`.
- [x] **Step 3: Confirmation.** `delete` → `countChanges` in the worktree (0 for prunable) and `spaceOf` → the row shows `Delete this worktree?`, then the lines that apply: `closes space "<name>"`, `<N> uncommitted changes will be lost` (`1 uncommitted change`), `branch is merged and will be deleted`, `branch is kept: <reason>`, `detached, there is no branch to delete`, `the folder is already gone`; then `Cancel` and `Delete`.
- [x] **Step 4: Delete.** On `Delete`: `countChanges` again → `removeMode(shown, now)`; `"ask"` shows the confirmation again with the new count and stops. Else `run("space.close", { id })` if a space is open; prunable → `git worktree prune`, else `git worktree remove [--force] <path>`; if merged → `git branch -D <branch>`; if a branch was kept → the panel's note line and `notify({ level: "info" })` both say `Kept <branch>: <reason>`. Any git failure → its stderr in the error line, nothing further runs. Then refresh.
- [ ] **Step 5: Verify.** `herdr-app check herdr/mods/my-worktrees` → passes. Then the user runs `./common/herdr.sh` and `herdr-app do layout.switch --name my-layout`, and checks in this repo: the button shows; `Main` and `Current` rows have no `delete`; a merged worktree shows `Merged`; deleting a clean merged one removes folder and branch; a dirty one warns and is removed with `--force`; one with an open space closes it first; a non-merged one keeps its branch and says why.
- [x] **Step 6: Docs.** Tick every checkbox above as it is verified, record each deviation in **Deviations**, and check `CLAUDE.md` and the spec still say nothing untrue (the `herdr.sh` entry-point line lists no panels, so it needs no change unless that changed).
