// Which GitLab or GitHub repo the focused terminal's folder belongs to. The tabs
// mod asks on every render and hands the answer to my-mrs as shared "my.repo".
import { exec, focused, panes, setShared, spaces } from "herdr";

const answers = new Map();
let published;

function location() {
  const space = spaces().find((s) => s.active), f = focused();
  const pane = f?.pane ? panes().find((p) => p.pane === f.pane) : null;
  const on = f?.pane === null ? (f.terminal?.includes("/") ? f.terminal.split("/")[0] : null) : space?.machine ?? null;
  return { cwd: pane?.cwd || f?.cwd || space?.folder, on };
}

// git@host:group/repo.git, https://host/group/repo.git, ssh://git@host:22/group/repo.git
function parseOrigin(url) {
  const match = /^(?:[a-z+]+:\/\/)?(?:[^@/]+@)?([^/:]+)(?::\d+)?[:/](.+?)(?:\.git)?\/?$/.exec(url.trim());
  if (!match) return null;
  const [, host, path] = match;
  const forge = /gitlab/i.test(host) ? "gitlab" : /github/i.test(host) ? "github" : null;
  // A host without a dot is an ssh-config alias, which glab and gh can't resolve.
  return forge && { forge, host: host.includes(".") ? host : null, path };
}

function publish(repo) {
  const value = JSON.stringify(repo);
  if (value === published) return;
  published = value;
  setShared("my.repo", repo);
}

// The repo, null when it is neither GitLab nor GitHub, undefined while first asked.
export function repoSpace(cx) {
  const { cwd, on } = location();
  if (!cwd) return null;
  const key = JSON.stringify([cwd, on]);
  if (!answers.has(key)) {
    answers.set(key, undefined);
    cx.spawn(async (cx) => {
      try {
        const r = await exec("git", ["remote", "get-url", "origin"], { cwd, on });
        answers.set(key, r.code === 0 ? parseOrigin(r.stdout) : null);
        cx.notify();
      } catch {
        // Machine offline or folder gone: forget it so a later render asks again.
        answers.delete(key);
      }
    });
  }
  const repo = answers.get(key);
  if (repo) publish(repo);
  return repo;
}
