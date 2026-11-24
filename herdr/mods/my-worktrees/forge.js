// The GitLab MR or GitHub PR behind each worktree branch, in one GraphQL request
// for all of them. Imports nothing from Herdr, so plain `node --test` can run it:
// the panel hands in `run`, which starts glab or gh on this computer, like my-prs
// does, whichever machine the repo is on. Hosts and logins come from their own config.

/** @typedef {import("./git.js").MR} MR */
/** @typedef {{ forge: "gitlab" | "github", host: string | null, path: string }} Forge */
/** @typedef {(tool: string, args: string[]) => Promise<{ code: number, stdout: string, stderr: string }>} Run */

const q = (value) => JSON.stringify(value);

export function gitlabQuery(path, branches) {
  return `query { project(fullPath: ${q(path)}) { mergeRequests(sourceBranches: ${q(branches)}, sort: UPDATED_DESC, first: 100) { nodes { iid state sourceBranch diffHeadSha webUrl } } } }`;
}

// One alias per branch: pullRequests filters by a single head branch only.
export function githubQuery(owner, name, branches) {
  const prs = branches.map((branch, i) =>
    `b${i}: pullRequests(headRefName: ${q(branch)}, first: 1, orderBy: {field: UPDATED_AT, direction: DESC}) { nodes { number state headRefOid url } }`);
  return `query { repository(owner: ${q(owner)}, name: ${q(name)}) { ${prs.join(" ")} } }`;
}

// "locked" is GitLab's state while a merge is being made.
const GITLAB_STATE = { opened: "open", locked: "open", merged: "merged", closed: "closed" };

/** @returns {Map<string, MR>} by branch; newest first, so the first one seen wins */
export function parseGitlab(json) {
  const mrs = new Map();
  for (const mr of json.data.project.mergeRequests.nodes) {
    if (mrs.has(mr.sourceBranch)) continue;
    mrs.set(mr.sourceBranch, { label: `MR !${mr.iid}`, state: GITLAB_STATE[mr.state] ?? "closed", head: mr.diffHeadSha, url: mr.webUrl });
  }
  return mrs;
}

/** @returns {Map<string, MR>} by branch */
export function parseGithub(json, branches) {
  const mrs = new Map();
  branches.forEach((branch, i) => {
    const pr = json.data.repository[`b${i}`]?.nodes[0];
    if (pr) mrs.set(branch, { label: `PR #${pr.number}`, state: pr.state.toLowerCase(), head: pr.headRefOid, url: pr.url });
  });
  return mrs;
}

const FORGES = {
  gitlab: { tool: "glab", query: ({ path }, branches) => gitlabQuery(path, branches), parse: (json) => parseGitlab(json) },
  github: {
    tool: "gh",
    query: ({ path }, branches) => {
      const at = path.indexOf("/");
      return githubQuery(path.slice(0, at), path.slice(at + 1), branches);
    },
    parse: (json, branches) => parseGithub(json, branches),
  },
};

/**
 * @param {Run} run
 * @param {Forge} forge
 * @param {string[]} branches
 * @returns {Promise<{ mrs: Map<string, MR>, error: string | null }>}
 */
export async function fetchMergeRequests(run, forge, branches) {
  const { tool, query, parse } = FORGES[forge.forge];
  if (!branches.length) return { mrs: new Map(), error: null };
  const args = ["api", "graphql", ...(forge.host ? ["--hostname", forge.host] : []), "-f", `query=${query(forge, branches)}`];
  let result;
  try {
    result = await run(tool, args);
  } catch {
    return { mrs: new Map(), error: `${tool} is not installed` };
  }
  if (result.code !== 0) {
    const stderr = result.stderr.trim();
    if (/401|unauthorized|auth login/i.test(stderr)) return { mrs: new Map(), error: `${tool}: not authorized` };
    return { mrs: new Map(), error: `${tool}: ${stderr.split("\n")[0] || `exited with ${result.code}`}` };
  }
  try {
    return { mrs: parse(JSON.parse(result.stdout), branches), error: null };
  } catch (error) {
    return { mrs: new Map(), error: `Unexpected ${tool} output: ${error}` };
  }
}
