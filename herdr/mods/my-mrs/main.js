// Right-side panel: the open GitLab merge requests I authored, in every project.
// The GitLab host and login come from glab's own config, never from this repo.
import { View, div } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { exec, notify, theme, window } from "herdr";

const QUERY = "merge_requests?scope=created_by_me&state=opened&per_page=50&with_labels_details=true";
const REFRESH_MS = 120000;

function openInBrowser(url) {
  const opener = window()?.platform === "macos" ? "open" : "xdg-open";
  exec(opener, [url]).catch((error) => notify({ title: "Could not open the link", body: `${error}`, level: "error" }));
}

// mise activates in interactive shells only, and Herdr's PATH comes from the login
// shell, so a glab installed through mise has to be asked of mise.
async function runGlab(args) {
  try {
    return await exec("glab", args);
  } catch {
    const found = await exec("mise", ["which", "glab"]);
    if (found.code !== 0) throw new Error("glab is not installed");
    return exec(found.stdout.trim(), args);
  }
}

export default class MyMrs extends View {
  init(_props, cx) {
    this.mrs = [];
    this.error = null;
    this.loading = true;
    this.refresh(cx);
    cx.timer.every(REFRESH_MS, (cx) => this.refresh(cx));
  }

  refresh(cx) {
    cx.spawn(async (cx) => {
      this.loading = true;
      cx.notify();
      await this.load();
      this.loading = false;
      cx.notify();
    });
  }

  async load() {
    let result;
    try {
      result = await runGlab(["api", QUERY]);
    } catch {
      this.mrs = [];
      this.error = "glab не встановлено";
      return;
    }
    if (result.code !== 0) {
      const stderr = result.stderr.trim();
      if (/401|unauthorized/i.test(stderr)) this.mrs = [];
      this.error = /401|unauthorized/i.test(stderr)
        ? "не авторизовано"
        : stderr || `glab exited with ${result.code}`;
      return;
    }
    try {
      this.mrs = JSON.parse(result.stdout);
      this.error = null;
    } catch (error) {
      this.error = `Unexpected glab output: ${error}`;
    }
  }

  row(mr, t) {
    return v_flex().id(`mr-${mr.id}`).flex_none().px(8).py(6).gap(2).rounded(7).cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .on_click(() => openInBrowser(mr.web_url))
      .child(h_flex().gap(6).items_center().min_w(0)
        .when(mr.draft, (e) => e.child(div().flex_none().px(4).rounded(4).border_1().border_color(t.border).text_size(10).text_color(t.muted).child("Draft")))
        .child(div().flex_1().min_w(0).truncate().child(mr.title)))
      .child(div().truncate().text_size(11).text_color(t.dim).child(mr.references.full))
      .when(mr.labels.length > 0, (e) => e.child(h_flex().flex_wrap().gap(4).pt(2).children(mr.labels.map((label) =>
        div().px(5).py(1).rounded(4).bg(label.color).text_size(10).text_color(label.text_color).child(label.name)))));
  }

  render(cx) {
    const t = theme();
    const empty = this.loading ? "Loading merge requests…" : "No open merge requests";
    return v_flex().id("my-mrs").size_full().min_h(0).rounded(10).overflow_hidden().bg(t.background)
      .border_1().border_color(t.border).text_color(t.foreground).text_size(13)
      .child(h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
        .child(div().font_semibold().child("Merge requests"))
        .child(div().px(5).py(1).rounded(4).border_1().border_color(t.border).text_size(10).text_color(t.muted).child(`${this.mrs.length} open`))
        .child(div().flex_1())
        .child(div().id("mrs-refresh").size(22).flex().items_center().justify_center().rounded(5).cursor_pointer().text_color(t.dim)
          .hover((s) => s.bg(t.hover).text_color(t.foreground))
          .on_click((_e, cx) => this.refresh(cx))
          .child("↻")))
      .when(Boolean(this.error), (e) => e.child(div().px(14).py(10).text_color(t.ansi1).child(this.error)))
      .child(v_flex().id("mrs-list").flex_1().min_h(0).overflow_y_scrollbar().p(6)
        .children(this.mrs.map((mr) => this.row(mr, t)))
        .when(!this.mrs.length && !this.error, (e) => e.child(div().p(8).text_color(t.dim).child(empty))));
  }
}
