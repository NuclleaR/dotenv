// Right-side panel: every container on the machine of the focused terminal, grouped
// by compose project, with restart, stop and remove. Starting is left to the
// project's own scripts, so a stopped container only offers remove.
import { View, div, svg } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { exec, focused, spaces, theme } from "herdr";

// One JSON object per line. Built field by field rather than `{{json .}}`, which
// hands the labels over as one comma-joined string.
const PS_FORMAT = "{" + [
  `"id":{{json .ID}}`,
  `"name":{{json .Names}}`,
  `"image":{{json .Image}}`,
  `"state":{{json .State}}`,
  `"status":{{json .Status}}`,
  `"project":{{json (.Label "com.docker.compose.project")}}`,
].join(",") + "}";

const ACTIONS = {
  restart: (id) => ["restart", id],
  stop: (id) => ["stop", id],
  remove: (id) => ["rm", "-f", id],
};

// stop and restart wait out the container's grace period first.
const ACTION_TIMEOUT = 120_000;

// The same machine the tabs mod's location() picks for the focused terminal.
function machine() {
  const f = focused(), space = spaces().find((s) => s.active);
  if (f?.pane === null) return f.terminal?.includes("/") ? f.terminal.split("/")[0] : null;
  return space?.machine ?? null;
}

function isUp(container) {
  return ["running", "restarting", "paused"].includes(container.state);
}

function stateColor(state, t) {
  if (state === "running") return t.ansi2;
  if (state === "restarting" || state === "paused") return t.ansi3;
  if (state === "dead") return t.ansi1;
  return t.dim;
}

// Compose projects by name, then whatever was started without compose.
function groupContainers(containers) {
  const groups = new Map();
  for (const container of containers) {
    const group = container.project || "";
    if (!groups.has(group)) groups.set(group, []);
    groups.get(group).push(container);
  }
  for (const list of groups.values()) list.sort((a, b) => a.name.localeCompare(b.name));
  return [...groups.entries()].sort(([a], [b]) => {
    if (!a !== !b) return a ? -1 : 1;
    return a.localeCompare(b);
  });
}

function parseContainers(stdout) {
  return stdout.split("\n").filter((line) => line.trim()).map((line) => JSON.parse(line));
}

async function fetchContainers(on) {
  let result;
  try {
    result = await exec("docker", ["ps", "--all", "--no-trunc", "--format", PS_FORMAT], { on });
  } catch (error) {
    return { error: `${error}` };
  }
  if (result.code !== 0) return { error: result.stderr.trim() || `docker exited with ${result.code}` };
  try {
    return { groups: groupContainers(parseContainers(result.stdout)), error: null };
  } catch (error) {
    return { error: `Unexpected docker output: ${error}` };
  }
}

export default class MyDocker extends View {
  init() {
    this.groups = [];
    this.error = null;
    this.actionError = null;
    this.loading = false;
    this.request = 0;
    // The machine shown; undefined until the first render picks one.
    this.on = undefined;
    // Container id -> the action running on it.
    this.busy = new Map();
  }

  refresh(cx) {
    const on = this.on;
    const request = ++this.request;
    this.loading = true;
    cx.spawn(async (cx) => {
      const { groups, error } = await fetchContainers(on);
      // Another machine was picked meanwhile: its answer is the one to show.
      if (request !== this.request) return;
      if (groups) this.groups = groups;
      this.error = error;
      this.loading = false;
      cx.notify();
    });
  }

  act(container, action, cx) {
    if (this.busy.has(container.id)) return;
    const on = this.on;
    this.busy.set(container.id, action);
    cx.spawn(async (cx) => {
      let error = null;
      try {
        const result = await exec("docker", ACTIONS[action](container.id), { on, timeout: ACTION_TIMEOUT });
        if (result.code !== 0) error = result.stderr.trim() || `docker ${action} exited with ${result.code}`;
      } catch (e) {
        error = `${e}`;
      }
      this.busy.delete(container.id);
      if (on !== this.on) return;
      this.actionError = error && `${action} ${container.name}: ${error}`;
      this.refresh(cx);
      cx.notify();
    });
  }

  button(container, action, t) {
    return div().id(`docker-${container.id}-${action}`).px(6).py(2).rounded(5).border_1().border_color(t.border)
      .cursor_pointer().text_size(11).text_color(t.muted)
      .hover((s) => s.bg(t.hover).text_color(action === "remove" ? t.ansi1 : t.foreground))
      .on_click((_e, cx) => { this.act(container, action, cx); cx.notify(); })
      .child(action);
  }

  row(container, t) {
    const busy = this.busy.get(container.id);
    const actions = isUp(container) ? ["restart", "stop", "remove"] : ["remove"];
    return v_flex().id(`docker-${container.id}`).flex_none().px(8).py(5).gap(3).rounded(7)
      .child(h_flex().gap(6).items_center().min_w(0)
        .child(div().size(7).flex_none().rounded(4).bg(stateColor(container.state, t)))
        .child(div().flex_1().min_w(0).truncate().child(container.name)))
      .child(div().truncate().text_size(11).text_color(t.dim).child(`${container.image} · ${container.status}`))
      .child(h_flex().gap(4).items_center()
        .when(Boolean(busy), (e) => e
          .child(svg("mods/workspace-chrome/spinner.svg").size(12).text_color(t.accent).spin(900))
          .child(div().text_size(11).text_color(t.dim).child(`${busy}…`)))
        .when(!busy, (e) => e.children(actions.map((action) => this.button(container, action, t)))));
  }

  render(cx) {
    const t = theme();
    const on = machine();
    if (on !== this.on) {
      this.on = on;
      this.groups = [];
      this.error = null;
      this.actionError = null;
      this.refresh(cx);
    }
    const all = this.groups.flatMap(([, containers]) => containers);
    const running = all.filter((c) => c.state === "running").length;
    const error = this.actionError || this.error;
    return v_flex().id("my-docker")
      .size_full().min_h(0).rounded(10).overflow_hidden().bg(t.background)
      .border_1().border_color(t.border).text_color(t.foreground).text_size(13)
      .child(h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
        .child(div().font_semibold().child("Docker"))
        .child(div().px(5).py(1).rounded(4).border_1().border_color(t.border).text_size(10).text_color(t.muted)
          .child(`${running}/${all.length} running`))
        .when(Boolean(on), (e) => e.child(div().min_w(0).truncate().text_size(11).text_color(t.dim).child(on)))
        .child(div().flex_1())
        .child(div().id("docker-refresh").size(22).flex().items_center().justify_center().rounded(5).cursor_pointer().text_color(t.dim)
          .hover((s) => s.bg(t.hover).text_color(t.foreground))
          .on_click((_e, cx) => { this.actionError = null; this.refresh(cx); cx.notify(); })
          .child(this.loading ? svg("mods/workspace-chrome/spinner.svg").size(14).text_color(t.accent).spin(900) : "↻")))
      .when(Boolean(error), (e) => e.child(div().px(14).py(10).text_color(t.ansi1).child(error)))
      .child(v_flex().id("docker-list").flex_1().min_h(0).overflow_y_scrollbar().p(6)
        .children(this.groups.map(([group, containers]) => v_flex().flex_none().pb(6)
          .child(div().px(8).pt(4).pb(2).text_size(11).text_color(t.muted).child(group || "without compose"))
          .children(containers.map((container) => this.row(container, t)))))
        .when(!all.length && !this.error, (e) => e.child(div().p(8).text_color(t.dim).child(this.loading ? "Loading containers…" : "No containers"))));
  }
}
