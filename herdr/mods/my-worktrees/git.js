// What the Worktrees panel decides with git alone. Imports nothing from Herdr, so
// plain `node --test` can run it against real repos: the panel hands in a `git`
// bound to the repo or to one worktree, on the right machine.

/** @typedef {{ ok: boolean, out: string, err: string }} GitResult */
/** @typedef {(args: string[]) => Promise<GitResult>} Git */
/** @typedef {{ path: string, head: string, branch: string | null, main: boolean, prunable: boolean, locked: boolean }} Worktree */
/** @typedef {{ label: string, state: "merged" | "open" | "closed", head: string, url: string }} MR */
/** @typedef {{ badge: { text: string, kind: "ok" | "warn" | "muted" }, merged: boolean, reason: string | null }} MergeState */

/** @param {string} porcelain `git worktree list --porcelain` @returns {Worktree[]} */
export function parseWorktrees(porcelain) {
  return porcelain.split(/\n\n+/).filter((block) => block.trim()).map((block, index) => {
    const lines = block.split("\n");
    const line = (key) => lines.find((l) => l === key || l.startsWith(`${key} `));
    return {
      bare: Boolean(line("bare")),
      path: line("worktree")?.slice(9) ?? "",
      head: line("HEAD")?.slice(5) ?? "",
      branch: line("branch")?.slice(7).replace(/^refs\/heads\//, "") ?? null,
      // git always lists the main working tree first.
      main: index === 0,
      prunable: Boolean(line("prunable")),
      locked: Boolean(line("locked")),
    };
  }).filter((wt) => !wt.bare).map(({ bare, ...wt }) => wt);
}

/** The worktree a folder is in. The deepest wins: a linked worktree can sit inside the main one. */
export function currentWorktree(worktrees, cwd) {
  if (!cwd) return null;
  let found = null;
  for (const { path } of worktrees) {
    if ((cwd === path || cwd.startsWith(`${path}/`)) && (!found || path.length > found.length)) found = path;
  }
  return found;
}

/** Changed and untracked files, the ones `git worktree remove` refuses to lose. The
 *  flags win over a config that would hide untracked files or submodule changes. */
export async function countChanges(git) {
  const r = await git(["status", "--porcelain", "--untracked-files=normal", "--ignore-submodules=none"]);
  if (!r.ok) throw new Error(r.err || "git status failed");
  return r.out ? r.out.split("\n").length : 0;
}

/** The branch merges land on, as a remote-tracking ref: "origin/main". */
export async function defaultBase(git) {
  const head = await git(["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"]);
  if (head.ok && head.out) return head.out;
  for (const ref of ["origin/main", "origin/master"]) {
    if ((await git(["rev-parse", "--verify", "--quiet", `refs/remotes/${ref}`])).ok) return ref;
  }
  return null;
}

/** Commits only this worktree's HEAD reaches: a detached worktree's removal loses them. */
export async function strayCommits(git) {
  const r = await git(["rev-list", "--count", "HEAD", "--not", "--branches", "--tags", "--remotes"]);
  if (!r.ok) throw new Error(r.err || "git rev-list failed");
  return Number(r.out) || 0;
}

/**
 * What to do when a confirmation's Delete is clicked, from what it said and how
 * the worktree is now. Anything it did not mention — more changes, a new commit,
 * another space or terminal in there — makes it ask again instead of acting.
 * @param {{ changes: number, stray: number, others: number, space: string | null, head: string }} shown
 * @param {{ changes: number, stray: number, others: number, space: string | null, head: string, current: boolean }} now
 * @returns {"refuse" | "ask" | "plain" | "force"}
 */
export function deleteDecision(shown, now) {
  if (now.current) return "refuse";
  if (now.head !== shown.head || now.changes > shown.changes || now.stray > shown.stray
    || now.others > shown.others || (now.space && now.space !== shown.space)) return "ask";
  return now.changes ? "force" : "plain";
}

const plural = (n, one, many) => (n === 1 ? one : many);

function merged() {
  return { badge: { text: "Merged", kind: "ok" }, merged: true, reason: null };
}

// Whether tip is a commit of base's own line (base and its first parents). A branch
// that points there was created at main or reset to it and has nothing of its own:
// being an ancestor of main does not make it merged.
async function onBaseLine(git, tip, base) {
  if (!(await git(["merge-base", "--is-ancestor", tip, base])).ok) return false;
  // Base's line down to the first commit tip already has: when that is tip itself,
  // the last one listed has tip as its first parent.
  const r = await git(["rev-list", "--first-parent", "--parents", base, "--not", tip]);
  if (!r.ok) return false;
  if (!r.out) return true;
  return r.out.split("\n").pop().split(" ")[1] === tip;
}

// Whether base already has the branch: as ancestry (a merge commit), commit by
// commit (a rebase merge), or as one combined diff (a squash merge). `ahead` is the
// commits base has no equivalent of, null when git could not say.
async function inBase(git, tip, base) {
  if ((await git(["merge-base", "--is-ancestor", tip, base])).ok) return { merged: true, ahead: 0 };
  const cherry = await git(["cherry", base, tip]);
  const lines = cherry.ok && cherry.out ? cherry.out.split("\n") : [];
  const ahead = cherry.ok ? lines.filter((l) => l.startsWith("+")).length : null;
  if (lines.length && ahead === 0) return { merged: true, ahead: 0 };
  // The whole branch as one commit on its merge base: git cherry then finds the
  // squash commit by patch id. The commit is never referenced, gc drops it.
  const mb = await git(["merge-base", base, tip]);
  if (mb.ok) {
    const squash = await git(["-c", "user.name=squash-check", "-c", "user.email=squash-check",
      "commit-tree", "--no-gpg-sign", "-p", mb.out, "-m", "squash-check", `${tip}^{tree}`]);
    if (squash.ok && (await git(["cherry", base, squash.out])).out.startsWith("-")) return { merged: true, ahead: 0 };
  }
  return { merged: false, ahead };
}

/**
 * Whether a worktree's branch is merged, and what the row says about it. A merged
 * MR counts only when no local commit came after the one it merged.
 * @param {Git} git in the repo
 * @param {Worktree} wt with a branch
 * @param {MR | undefined} mr the branch's most recent MR or PR
 * @param {{ base: string | null, forge: "MR" | "PR" | null }} ctx forge: what its requests are called, null without one
 * @returns {Promise<MergeState>}
 */
export async function mergeState(git, wt, mr, { base, forge }) {
  const tip = wt.head;
  // Always "in" origin/main, and a fork's MR from its own main would match it too.
  if (base && wt.branch === base.slice(base.indexOf("/") + 1)) {
    return { badge: { text: "Default branch", kind: "muted" }, merged: false, reason: "it is the default branch" };
  }
  // A fast-forward merge leaves the MR's head on main's own line: that is still a merge.
  if (mr?.state === "merged" && tip === mr.head) return merged();
  if (base && await onBaseLine(git, tip, base)) {
    return { badge: { text: "No commits", kind: "muted" }, merged: false, reason: "it has no commits of its own" };
  }
  if (mr?.state === "merged") {
    if ((await git(["merge-base", "--is-ancestor", tip, mr.head])).ok) return merged();
    if ((await git(["cat-file", "-e", `${mr.head}^{commit}`])).ok) {
      // Commits neither the MR nor main has: main's own commits are not local work.
      const n = Number((await git(["rev-list", "--count", tip, "--not", mr.head, ...(base ? [base] : [])])).out) || 0;
      return {
        badge: { text: `Merged, +${n} local ${plural(n, "commit", "commits")}`, kind: "warn" },
        merged: false,
        reason: `merged, but ${n} local ${plural(n, "commit came", "commits came")} after it`,
      };
    }
    // Not fetched, or the branch was rewritten: let git compare the content.
    if (base && (await inBase(git, tip, base)).merged) return merged();
    return {
      badge: { text: "Merged, local differs", kind: "warn" },
      merged: false,
      reason: "merged, but the local branch differs from what was merged",
    };
  }
  if (mr?.state === "open") {
    return { badge: { text: `${mr.label} open`, kind: "warn" }, merged: false, reason: `${mr.label} is still open` };
  }
  const badge = mr ? { text: `${mr.label} closed`, kind: "muted" } : { text: "Not merged", kind: "muted" };
  if (!base) return { badge, merged: false, reason: "no origin/main or origin/master to compare with" };
  const check = await inBase(git, tip, base);
  if (check.merged) return merged();
  const missing = check.ahead
    ? `${check.ahead} ${plural(check.ahead, "commit is", "commits are")} not in ${base}`
    : `the changes are not in ${base}`;
  const reason = mr ? `${mr.label} was closed and ${missing}` : forge ? `no ${forge} found and ${missing}` : missing;
  return { badge, merged: false, reason };
}
