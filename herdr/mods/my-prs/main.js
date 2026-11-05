// Right-side panel: my open merge requests (GitLab) or pull requests (GitHub) in
// the repo of the focused terminal, which the my-tabs mod shares as "my.repo".
// Hosts and logins come from glab's and gh's own config, never from this repo.
import { View, div, svg } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { exec, focused, notify, panes, shared, spaces, theme, window } from "herdr";
import { openBranch } from "./worktree.js";

const REFRESH_MS = 120000;

// The focused terminal's folder and machine: the repo this list belongs to, since
// a click on the panel leaves the terminal focused.
function focusedPlace() {
  const space = spaces().find((s) => s.active), f = focused();
  const pane = f?.pane ? panes().find((p) => p.pane === f.pane) : null;
  const on = f?.pane === null ? (f.terminal?.includes("/") ? f.terminal.split("/")[0] : null) : space?.machine ?? null;
  return { cwd: pane?.cwd || f?.cwd || space?.folder, on };
}

function openInBrowser(url) {
  const opener = window()?.platform === "macos" ? "open" : "xdg-open";
  exec(opener, [url]).catch((error) => notify({ title: "Could not open the link", body: `${error}`, level: "error" }));
}

// mise activates in interactive shells only, and Herdr's PATH comes from the login
// shell, so a tool installed through mise has to be asked of mise.
async function runTool(tool, args) {
  try {
    return await exec(tool, args);
  } catch {
    const found = await exec("mise", ["which", tool]);
    if (found.code !== 0) throw new Error(`${tool} is not installed`);
    return exec(found.stdout.trim(), args);
  }
}

// GitHub only gives a label's background, so pick the text color for it.
function textOn(hex) {
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(hex.slice(i, i + 2), 16));
  return (r * 299 + g * 587 + b * 114) / 1000 > 128 ? "#1F1E24" : "#FFFFFF";
}

const GITLAB_STATUS = {
  conflict: { text: "Conflicts", kind: "bad" },
  discussions_not_resolved: { text: "Unresolved threads", kind: "warn" },
  need_rebase: { text: "Needs rebase", kind: "warn" },
  not_approved: { text: "Needs approval", kind: "warn" },
  mergeable: { text: "Ready", kind: "ok" },
  // GitLab computes the status lazily: with_merge_status_recheck asks it to, and
  // a later refresh gets the real one.
  unchecked: { text: "Checking", kind: "muted" },
  checking: { text: "Checking", kind: "muted" },
  // The Draft chip already says it.
  draft_status: null,
};

function gitlabStatus(status) {
  if (status in GITLAB_STATUS) return GITLAB_STATUS[status];
  return { text: status.replaceAll("_", " "), kind: "muted" };
}

function githubStatus(pr) {
  if (pr.mergeable === "CONFLICTING") return { text: "Conflicts", kind: "bad" };
  if (pr.isDraft) return null;
  if (pr.reviewDecision === "CHANGES_REQUESTED") return { text: "Changes requested", kind: "warn" };
  if (pr.mergeable === "UNKNOWN" || pr.mergeStateStatus === "UNKNOWN") return { text: "Checking", kind: "muted" };
  if (pr.mergeStateStatus === "BEHIND") return { text: "Needs rebase", kind: "warn" };
  if (pr.mergeStateStatus === "UNSTABLE") return { text: "Checks failing", kind: "bad" };
  if (pr.reviewDecision === "REVIEW_REQUIRED") return { text: "Needs review", kind: "warn" };
  if (pr.mergeStateStatus === "CLEAN" || pr.mergeStateStatus === "HAS_HOOKS") return { text: "Ready", kind: "ok" };
  return { text: pr.mergeStateStatus.toLowerCase().replaceAll("_", " "), kind: "muted" };
}

// CI as "ok", "bad", "running" or "other"; null when nothing ran.
const GITLAB_CI = {
  SUCCESS: "ok",
  FAILED: "bad",
  RUNNING: "running",
  PENDING: "running",
  CREATED: "running",
  PREPARING: "running",
  WAITING_FOR_RESOURCE: "running",
  WAITING_FOR_CALLBACK: "running",
  SCHEDULED: "running",
};

function githubCi(checks) {
  if (!checks.length) return null;
  // A check run has a status and a conclusion, a commit status only a state.
  const states = checks.map((check) => check.conclusion || check.state || check.status);
  if (states.some((s) => ["FAILURE", "ERROR", "TIMED_OUT", "STARTUP_FAILURE", "ACTION_REQUIRED"].includes(s))) return "bad";
  if (states.some((s) => ["PENDING", "EXPECTED", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED"].includes(s))) return "running";
  if (states.every((s) => ["SUCCESS", "NEUTRAL", "SKIPPED"].includes(s))) return "ok";
  return "other";
}

// The REST list has no pipelines, and one request per MR would be 35 of them. CI is
// a nicety, so a failure here leaves the list as it is, only without the dots.
async function addGitlabCi(items, { host, path }) {
  if (!items.length) return;
  const iids = items.map((item) => JSON.stringify(String(item.iid))).join(",");
  const query = `query { project(fullPath: ${JSON.stringify(path)}) { mergeRequests(iids: [${iids}]) { nodes { iid headPipeline { status } } } } }`;
  try {
    const result = await runTool("glab", ["api", "graphql", ...(host ? ["--hostname", host] : []), "-f", `query=${query}`]);
    if (result.code !== 0) return;
    const nodes = JSON.parse(result.stdout).data.project.mergeRequests.nodes;
    const status = new Map(nodes.map((node) => [node.iid, node.headPipeline?.status]));
    for (const item of items) {
      const value = status.get(String(item.iid));
      item.ci = value ? GITLAB_CI[value] ?? "other" : null;
    }
  } catch {}
}

const FORGES = {
  gitlab: {
    tool: "glab",
    title: "Merge requests",
    args: ({ host, path }) => [
      "api",
      ...(host ? ["--hostname", host] : []),
      `projects/${encodeURIComponent(path)}/merge_requests?scope=created_by_me&state=opened&order_by=updated_at&sort=desc&per_page=50&with_labels_details=true&with_merge_status_recheck=true`,
    ],
    item: (mr) => ({
      id: mr.id, title: mr.title, url: mr.web_url, draft: mr.draft, ref: mr.references.full, labels: mr.labels,
      branch: mr.source_branch, updated: mr.updated_at, iid: mr.iid, ci: null,
      // A draft or an unresolved thread hides a conflict from detailed_merge_status.
      status: mr.has_conflicts ? GITLAB_STATUS.conflict : gitlabStatus(mr.detailed_merge_status),
      comments: mr.user_notes_count,
    }),
  },
  github: {
    tool: "gh",
    title: "Pull requests",
    args: ({ host, path }) => [
      "pr", "list", "--repo", host ? `${host}/${path}` : path, "--author", "@me", "--state", "open",
      "--limit", "50", "--json", "number,title,url,isDraft,headRefName,updatedAt,statusCheckRollup,labels,mergeable,mergeStateStatus,reviewDecision,comments",
    ],
    item: (pr, { path }) => ({
      id: pr.number, title: pr.title, url: pr.url, draft: pr.isDraft, ref: `${path}#${pr.number}`,
      branch: pr.headRefName, updated: pr.updatedAt, ci: githubCi(pr.statusCheckRollup),
      labels: pr.labels.map((l) => ({ name: l.name, color: `#${l.color}`, text_color: textOn(l.color) })),
      status: githubStatus(pr), comments: pr.comments.length,
    }),
  },
};

async function fetchItems(repo) {
  const forge = FORGES[repo.forge];
  let result;
  try {
    result = await runTool(forge.tool, forge.args(repo));
  } catch {
    return { items: [], error: `${forge.tool} не встановлено` };
  }
  if (result.code !== 0) {
    const stderr = result.stderr.trim();
    if (/401|unauthorized|auth login/i.test(stderr)) return { items: [], error: "не авторизовано" };
    return { error: stderr || `${forge.tool} exited with ${result.code}` };
  }
  try {
    const items = JSON.parse(result.stdout).map((item) => forge.item(item, repo));
    // Most recently updated first. gh has no reliable order of its own for this.
    items.sort((a, b) => Date.parse(b.updated) - Date.parse(a.updated));
    if (repo.forge === "gitlab") await addGitlabCi(items, repo);
    return { items, error: null };
  } catch (error) {
    return { error: `Unexpected ${forge.tool} output: ${error}` };
  }
}

export default class MyPrs extends View {
  init(_props, cx) {
    this.mrs = [];
    this.error = null;
    this.loading = false;
    this.request = 0;
    cx.timer.every(REFRESH_MS, (cx) => { this.refresh(cx); cx.notify(); });
  }

  refresh(cx) {
    const repo = shared("my.repo");
    if (!repo) return;
    const request = ++this.request;
    this.loading = true;
    cx.spawn(async (cx) => {
      const { items, error } = await fetchItems(repo);
      // Another repo was picked meanwhile: its answer is the one to show.
      if (request !== this.request) return;
      if (items) this.mrs = items;
      this.error = error;
      this.loading = false;
      cx.notify();
    });
  }

  openWorktree(mr, cx) {
    if (this.opening) return;
    this.opening = mr.id;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        await openBranch(mr.branch, focusedPlace());
      } catch (error) {
        notify({ title: `Could not open ${mr.branch}`, body: error.message ?? `${error}`, level: "error" });
      }
      this.opening = null;
      cx.notify();
    });
  }

  // For a browser that isn't the system's default, where `open` would land.
  copyLink(mr, cx) {
    cx.write_to_clipboard(mr.url);
    this.copied = mr.id;
    cx.notify();
    cx.timer.after(1500, (cx) => {
      if (this.copied !== mr.id) return;
      this.copied = null;
      cx.notify();
    });
  }

  row(mr, t) {
    const statusColor = { bad: t.ansi1, warn: t.blocked, ok: t.ansi2, muted: t.dim };
    const ciColor = { ok: t.ansi2, bad: t.ansi1, running: t.working, other: t.dim };
    const action = (id) => div().id(`${id}-${mr.id}`).flex_none().size(26).flex().items_center().justify_center().rounded(5).cursor_pointer()
      .text_size(15).text_color(t.muted)
      .hover((s) => s.bg(t.raised).text_color(t.foreground));
    // Side by side, not nested: a click on these must never reach the worktree.
    return v_flex().id(`mr-row-${mr.id}`).flex_none().rounded(7)
      .hover((s) => s.bg(t.hover))
      .child(h_flex().id(`mr-title-${mr.id}`).px(8).pt(6).gap(6).items_center().min_w(0).cursor_pointer()
        .on_click((_e, cx) => this.openWorktree(mr, cx))
        .when(mr.draft, (e) => e.child(div().flex_none().px(4).rounded(4).border_1().border_color(t.border).text_size(10).text_color(t.muted).child("Draft")))
        .child(div().flex_1().min_w(0).truncate().child(mr.title)))
      .child(h_flex().items_end().min_w(0).pr(3).pb(3)
        .child(v_flex().id(`mr-${mr.id}`).flex_1().min_w(0).pl(8).pb(3).gap(4).cursor_pointer()
          .on_click((_e, cx) => this.openWorktree(mr, cx))
          .child(div().truncate().text_size(11).text_color(t.dim).child(mr.ref))
          .when(mr.labels.length > 0, (e) => e.child(h_flex().flex_wrap().gap(4).children(mr.labels.map((label) =>
            div().px(5).py(1).rounded(4).bg(label.color).text_size(10).text_color(label.text_color).child(label.name))))))
        .child(h_flex().flex_none().items_center().gap(8).pl(8).text_size(11)
        .when(mr.comments > 0, (e) => e.child(div().text_color(t.dim).child(`${mr.comments} ${mr.comments === 1 ? "comment" : "comments"}`)))
        .when(Boolean(mr.ci), (e) => e.child(div().flex_none().size(8).rounded(4).bg(ciColor[mr.ci])))
        .when(Boolean(mr.status), (e) => e.child(div().text_color(statusColor[mr.status.kind]).child(mr.status.text)))
        .child(h_flex()
        .child(action("mr-copy")
          .on_click((_e, cx) => this.copyLink(mr, cx))
          .child(this.copied === mr.id
            ? svg("mods/workspace-chrome/check.svg").size(14).text_color(t.ansi2)
            : svg("mods/my-tabs/copy.svg").size(13)))
        .child(action("mr-browser")
          .on_click(() => openInBrowser(mr.url))
          .child(this.opening === mr.id
            ? svg("mods/workspace-chrome/spinner.svg").size(14).text_color(t.accent).spin(900)
            : "↗")))));
  }

  render(cx) {
    const t = theme();
    const repo = shared("my.repo");
    const key = JSON.stringify(repo);
    if (key !== this.key) {
      this.key = key;
      this.mrs = [];
      this.error = null;
      this.refresh(cx);
    }
    const title = FORGES[repo?.forge]?.title ?? "Merge requests";
    const empty = this.loading ? `Loading ${title.toLowerCase()}…` : `No open ${title.toLowerCase()}`;
    return v_flex().id("my-prs").size_full().min_h(0).rounded(10).overflow_hidden().bg(t.background)
      .border_1().border_color(t.border).text_color(t.foreground).text_size(13)
      .child(h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
        .child(div().font_semibold().child(title))
        .child(div().px(5).py(1).rounded(4).border_1().border_color(t.border).text_size(10).text_color(t.muted).child(`${this.mrs.length} open`))
        .child(div().flex_1())
        .child(div().id("prs-refresh").size(22).flex().items_center().justify_center().rounded(5).cursor_pointer().text_color(t.dim)
          .hover((s) => s.bg(t.hover).text_color(t.foreground))
          .on_click((_e, cx) => { this.refresh(cx); cx.notify(); })
          .child(this.loading ? svg("mods/workspace-chrome/spinner.svg").size(14).text_color(t.accent).spin(900) : "↻")))
      .when(Boolean(this.error), (e) => e.child(div().px(14).py(10).text_color(t.ansi1).child(this.error)))
      .child(v_flex().id("prs-list").flex_1().min_h(0).overflow_y_scrollbar().p(6)
        .children(this.mrs.map((mr) => this.row(mr, t)))
        .when(!this.mrs.length && !this.error, (e) => e.child(div().p(8).text_color(t.dim).child(empty))));
  }
}
