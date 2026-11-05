// Opens an MR's or PR's branch in its own space, on the machine of the repo.
//
// The shipped worktree mod is no use here: for a branch with no local copy it runs
// `git worktree add -b <branch> <path> HEAD`, a new branch from HEAD without the
// MR's commits. Checkouts do go where it puts them, so they nest under the repo.
import { exec, panes, run, spaces } from "herdr";

async function git(cwd, on, args) {
  const r = await exec("git", args, { cwd, on });
  return { ok: r.code === 0, out: r.stdout.trim(), err: r.stderr.trim() };
}

async function must(cwd, on, args) {
  const r = await git(cwd, on, args);
  if (!r.ok) throw new Error(r.err || `git ${args[0]} failed`);
  return r.out;
}

// Every checkout of the repo: { path, branch }.
async function checkouts(cwd, on) {
  const list = await must(cwd, on, ["worktree", "list", "--porcelain"]);
  return list.split(/\n\n+/).map((block) => {
    const lines = block.split("\n");
    return {
      path: lines.find((l) => l.startsWith("worktree "))?.slice(9),
      branch: lines.find((l) => l.startsWith("branch "))?.slice(7).replace(/^refs\/heads\//, "") ?? null,
    };
  });
}

// Where a space is now: its first terminal's live folder, else where it was made.
function place(space) {
  const tabs = new Set(space.tabs.map((t) => t.id));
  return panes().find((p) => tabs.has(p.tab) && p.cwd)?.cwd || space.folder || null;
}

// The space showing a checkout. The deepest checkout wins: a linked worktree can
// sit inside the main one, and a space in there is not showing the main one.
function spaceOf(path, all, on) {
  const inside = (at, dir) => at === dir || at.startsWith(`${dir}/`);
  return spaces().find((space) => {
    if ((space.machine ?? null) !== (on ?? null)) return false;
    const at = place(space);
    if (!at || !inside(at, path)) return false;
    return !all.some((c) => c.path && c.path !== path && c.path.length > path.length && inside(at, c.path));
  });
}

async function addWorktree(branch, cwd, on) {
  const common = await must(cwd, on, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
  const main = common.endsWith("/.git") ? common.slice(0, -5) : common;
  const home = (await exec("sh", ["-c", 'printf %s "$HOME"'], { on })).stdout.trim();
  const slug = branch.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "");
  const path = `${home}/.herdr/worktrees/${main.split("/").pop()}/${slug}`;

  await must(cwd, on, ["fetch", "origin", `refs/heads/${branch}:refs/remotes/origin/${branch}`]);
  // A local copy may hold unpushed work, so it is used as it is, never moved.
  const local = await git(cwd, on, ["show-ref", "--verify", "--quiet", `refs/heads/${branch}`]);
  await must(cwd, on, local.ok
    ? ["worktree", "add", path, branch]
    : ["worktree", "add", "--track", "-b", branch, path, `origin/${branch}`]);
  return path;
}

// Throws with git's own message when it can't be done.
export async function openBranch(branch, { cwd, on }) {
  const all = await checkouts(cwd, on);
  const path = all.find((c) => c.branch === branch)?.path ?? await addWorktree(branch, cwd, on);
  const space = spaceOf(path, all, on);
  // Left unnamed, so the space follows its folder and nests under the repo.
  if (space) run("space.select", { id: space.id });
  else run("space.new", { folder: path, machine: on });
}
