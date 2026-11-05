// Right-side panel: my open merge requests (GitLab) or pull requests (GitHub) in
// the repo of the focused terminal, which the my-tabs mod shares as "my.repo".
// Hosts and logins come from glab's and gh's own config, never from this repo.
import { View, div } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { exec, notify, shared, theme, window } from "herdr";

const REFRESH_MS = 120000;

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

const FORGES = {
  gitlab: {
    tool: "glab",
    title: "Merge requests",
    args: ({ host, path }) => [
      "api",
      ...(host ? ["--hostname", host] : []),
      `projects/${encodeURIComponent(path)}/merge_requests?scope=created_by_me&state=opened&per_page=50&with_labels_details=true`,
    ],
    item: (mr) => ({
      id: mr.id, title: mr.title, url: mr.web_url, draft: mr.draft, ref: mr.references.full, labels: mr.labels,
    }),
  },
  github: {
    tool: "gh",
    title: "Pull requests",
    args: ({ host, path }) => [
      "pr", "list", "--repo", host ? `${host}/${path}` : path, "--author", "@me", "--state", "open",
      "--limit", "50", "--json", "number,title,url,isDraft,labels",
    ],
    item: (pr, { path }) => ({
      id: pr.number, title: pr.title, url: pr.url, draft: pr.isDraft, ref: `${path}#${pr.number}`,
      labels: pr.labels.map((l) => ({ name: l.name, color: `#${l.color}`, text_color: textOn(l.color) })),
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
    return { items: JSON.parse(result.stdout).map((item) => forge.item(item, repo)), error: null };
  } catch (error) {
    return { error: `Unexpected ${forge.tool} output: ${error}` };
  }
}

export default class MyMrs extends View {
  init(_props, cx) {
    this.mrs = [];
    this.error = null;
    this.loading = false;
    this.request = 0;
    cx.timer.every(REFRESH_MS, (cx) => this.refresh(cx));
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

  row(mr, t) {
    return v_flex().id(`mr-${mr.id}`).flex_none().px(8).py(6).gap(2).rounded(7).cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .on_click(() => openInBrowser(mr.url))
      .child(h_flex().gap(6).items_center().min_w(0)
        .when(mr.draft, (e) => e.child(div().flex_none().px(4).rounded(4).border_1().border_color(t.border).text_size(10).text_color(t.muted).child("Draft")))
        .child(div().flex_1().min_w(0).truncate().child(mr.title)))
      .child(div().truncate().text_size(11).text_color(t.dim).child(mr.ref))
      .when(mr.labels.length > 0, (e) => e.child(h_flex().flex_wrap().gap(4).pt(2).children(mr.labels.map((label) =>
        div().px(5).py(1).rounded(4).bg(label.color).text_size(10).text_color(label.text_color).child(label.name)))));
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
    return v_flex().id("my-mrs").size_full().min_h(0).rounded(10).overflow_hidden().bg(t.background)
      .border_1().border_color(t.border).text_color(t.foreground).text_size(13)
      .child(h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
        .child(div().font_semibold().child(title))
        .child(div().px(5).py(1).rounded(4).border_1().border_color(t.border).text_size(10).text_color(t.muted).child(`${this.mrs.length} open`))
        .child(div().flex_1())
        .child(div().id("mrs-refresh").size(22).flex().items_center().justify_center().rounded(5).cursor_pointer().text_color(t.dim)
          .hover((s) => s.bg(t.hover).text_color(t.foreground))
          .on_click((_e, cx) => { this.refresh(cx); cx.notify(); })
          .child("↻")))
      .when(Boolean(this.error), (e) => e.child(div().px(14).py(10).text_color(t.ansi1).child(this.error)))
      .child(v_flex().id("mrs-list").flex_1().min_h(0).overflow_y_scrollbar().p(6)
        .children(this.mrs.map((mr) => this.row(mr, t)))
        .when(!this.mrs.length && !this.error, (e) => e.child(div().p(8).text_color(t.dim).child(empty))));
  }
}
