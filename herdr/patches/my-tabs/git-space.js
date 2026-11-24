// The git repo the focused terminal's folder belongs to, for my-worktrees. The tabs
// mod asks on every render and hands the answer over as shared "my.git":
// { common: the repo's git common dir, on: its machine, forge: what repoSpace found }.
import { exec, setShared } from "herdr";
import { location } from "./repo-space.js";

const answers = new Map();
let published;

function publish(git) {
  const value = JSON.stringify(git);
  if (value === published) return;
  published = value;
  setShared("my.git", git);
}

// { common, on }, null outside a git repo, undefined while first asked. `repo` is
// repoSpace's answer for the same folder: published only once that is known too,
// so the panel does not ask for its merge requests twice.
export function gitSpace(cx, repo) {
  const { cwd, on } = location();
  if (!cwd) return null;
  const key = JSON.stringify([cwd, on]);
  if (!answers.has(key)) {
    answers.set(key, undefined);
    cx.spawn(async (cx) => {
      try {
        const r = await exec("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, on });
        answers.set(key, r.code === 0 ? { common: r.stdout.trim(), on } : null);
        cx.notify();
      } catch {
        // Machine offline or folder gone: forget it so a later render asks again.
        answers.delete(key);
      }
    });
  }
  const git = answers.get(key);
  if (git && repo !== undefined) publish({ ...git, forge: repo || null });
  return git;
}
