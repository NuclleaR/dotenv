// Which Herdr space shows a worktree, and opening one. `place` and `spaceOf` are a
// copy of the ones in my-prs/worktree.js: each mod is loaded on its own, and Herdr
// is not known to resolve imports across mod folders.
import { panes, run, spaces } from "herdr";

const inside = (at, dir) => at === dir || at.startsWith(`${dir}/`);

// In `path` itself, not in a linked worktree nested inside it.
function within(at, path, all) {
  return inside(at, path) && !all.some((c) => c.path && c.path !== path && c.path.length > path.length && inside(at, c.path));
}

// Where a space is now: its first terminal's live folder, else where it was made.
function place(space) {
  const tabs = new Set(space.tabs.map((t) => t.id));
  return panes().find((p) => tabs.has(p.tab) && p.cwd)?.cwd || space.folder || null;
}

const onMachine = (space, on) => (space.machine ?? null) === (on ?? null);

// The space showing a worktree. The deepest worktree wins: a linked worktree can
// sit inside the main one, and a space in there is not showing the main one.
export function spaceOf(path, all, on) {
  return spaces().find((space) => {
    if (!onMachine(space, on)) return false;
    const at = place(space);
    return Boolean(at) && within(at, path, all);
  });
}

// Terminals inside a worktree in other spaces than `spaceId`, which a delete closes:
// they stay behind in a folder that no longer exists.
export function othersIn(path, all, on, spaceId) {
  let count = 0;
  for (const space of spaces()) {
    if (!onMachine(space, on) || space.id === spaceId) continue;
    const tabs = new Set(space.tabs.map((t) => t.id));
    count += panes().filter((p) => tabs.has(p.tab) && p.terminal && p.cwd && within(p.cwd, path, all)).length;
  }
  return count;
}

// Left unnamed, so a new space follows its folder and nests under the repo.
export function openSpace(path, all, on) {
  const space = spaceOf(path, all, on);
  if (space) run("space.select", { id: space.id });
  else run("space.new", { folder: path, machine: on });
}
