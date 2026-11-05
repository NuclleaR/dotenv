// Right-side panel: the recipes of the justfile above the focused terminal, which
// the my-tabs mod shares as "my.just". A click runs one in a new terminal below.
import { View, div, svg } from "gpui-kit";
import { h_flex, v_flex, Input, InputState } from "gpui-base";
import { exec, run, shared, theme } from "herdr";

// terminal.open runs its argv directly: without an interactive shell mise is not
// active, and the pane would close with the recipe. So the recipe runs inside one,
// and that shell stays for what comes after. The trap keeps this wrapper alive
// through Ctrl-C; the child shell gets the default back.
const RUN_IN_SHELL = 'trap : INT; "${SHELL:-sh}" -ic "$1"; exec "${SHELL:-sh}" -i';

// exec gets no interactive shell either, so it has to look for a just from mise.
const FIND_JUST = `PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
command -v just >/dev/null && exec just "$@"
command -v mise >/dev/null && exec mise exec -- just "$@"
exit 127`;

const PARAM_PREFIX = { star: "*", plus: "+", singular: "" };

function paramLabel(param) {
  const label = `${PARAM_PREFIX[param.kind] ?? ""}${param.name}`;
  return param.default === null ? label : `${label}=${param.default}`;
}

// A `|` outside any brackets separates alternatives.
function splitAlternatives(usage) {
  const parts = [""];
  let depth = 0;
  for (const char of usage) {
    if ("[<(".includes(char)) depth++;
    if ("]>)".includes(char)) depth--;
    if (char === "|" && depth === 0) parts.push("");
    else parts[parts.length - 1] += char;
  }
  return parts.map((part) => part.trim());
}

// Just has no notion of subcommands, so they are read from the usage in a recipe's
// doc: `just proxy [up|down]` or `just user gen [OPTIONS] | del USER_ID`. Without a
// `|` it is only an example, as in `just web test src/components`.
function subcommands(recipe) {
  const usage = recipe.doc?.match(new RegExp("`just\\s+" + recipe.name + "\\s+([^`]*)`"))?.[1].trim();
  if (!usage?.includes("|")) return [];
  const inner = usage.match(/^\[([^\]]*)\]$/)?.[1] ?? usage;
  const found = splitAlternatives(inner).map((alternative) => {
    const [name, ...rest] = alternative.split(/\s+/);
    const required = rest.join(" ").replace(/\[[^\]]*\]/g, "").trim();
    return { name, hint: alternative, needsInput: required.length > 0 };
  });
  return found.every((sub) => /^[a-z][\w:-]*$/.test(sub.name)) ? found : [];
}

// Ungrouped first, then by group name: the order of `just --list`.
function groupRecipes(recipes) {
  const groups = new Map();
  for (const recipe of Object.values(recipes)) {
    if (recipe.private) continue;
    const group = recipe.attributes?.find((a) => a?.group)?.group ?? "";
    if (!groups.has(group)) groups.set(group, []);
    groups.get(group).push(recipe);
  }
  return [...groups.entries()].sort(([a], [b]) => a.localeCompare(b));
}

async function fetchRecipes({ root, on }) {
  let result;
  try {
    result = await exec("sh", ["-c", FIND_JUST, "sh", "--dump", "--dump-format", "json"], { cwd: root, on });
  } catch (error) {
    return { error: `${error}` };
  }
  if (result.code === 127) return { groups: [], error: "just не встановлено" };
  if (result.code !== 0) return { error: result.stderr.trim() || `just exited with ${result.code}` };
  try {
    return { groups: groupRecipes(JSON.parse(result.stdout).recipes), error: null };
  } catch (error) {
    return { error: `Unexpected just output: ${error}` };
  }
}

export default class MyJust extends View {
  init(_props, cx) {
    this.groups = [];
    this.error = null;
    this.loading = false;
    this.request = 0;
    this.asking = null;
    this.handle = cx.focus_handle();
  }

  refresh(cx) {
    const just = shared("my.just");
    if (!just) return;
    const request = ++this.request;
    this.loading = true;
    cx.spawn(async (cx) => {
      const { groups, error } = await fetchRecipes(just);
      // Another project was picked meanwhile: its answer is the one to show.
      if (request !== this.request) return;
      if (groups) this.groups = groups;
      this.error = error;
      this.loading = false;
      cx.notify();
    });
  }

  // The shell parses the typed arguments, so `--grep "a b"` works as usual.
  start(name, args) {
    this.asking = null;
    run("terminal.open", {
      argv: ["sh", "-c", RUN_IN_SHELL, "just", `just ${name} ${args}`.trim()],
      folder: shared("my.just").root,
      place: "down",
      name: `just ${name}`,
    });
  }

  // A recipe with parameters asks for them first, in its own row.
  click(recipe, cx) {
    if (!recipe.parameters.length) this.start(recipe.name, "");
    else if (this.asking === recipe.name) this.asking = null;
    else this.ask(recipe, "", null);
    cx.notify();
  }

  ask(recipe, value, hint) {
    this.asking = recipe.name;
    this.hint = hint;
    this.input = InputState.new({ value });
    this.input.on("submit", (_e, cx) => { this.start(recipe.name, this.input.value()); cx.notify(); });
    this.input.focus();
  }

  clickSub(recipe, sub, cx) {
    if (sub.needsInput) this.ask(recipe, `${sub.name} `, sub.hint);
    else this.start(recipe.name, sub.name);
    cx.notify();
  }

  row(recipe, t) {
    const asking = this.asking === recipe.name;
    const subs = subcommands(recipe);
    return v_flex().flex_none().rounded(7).when(asking, (e) => e.bg(t.raised))
      .child(v_flex().id(`just-${recipe.name}`).px(8).py(5).gap(1).rounded(7).cursor_pointer()
        .hover((s) => s.bg(t.hover))
        .on_click((_e, cx) => this.click(recipe, cx))
        .child(h_flex().gap(6).items_center().min_w(0)
          .child(div().flex_none().child(recipe.name))
          .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.dim).child(recipe.parameters.map(paramLabel).join(" "))))
        .when(Boolean(recipe.doc), (e) => e.child(div().truncate().text_size(11).text_color(t.dim).child(recipe.doc))))
      .when(subs.length > 0, (e) => e.child(h_flex().flex_wrap().gap(4).px(8).pb(6).children(subs.map((sub) =>
        div().id(`just-${recipe.name}-${sub.name}`).px(6).py(2).rounded(5).border_1().border_color(t.border).cursor_pointer()
          .text_size(11).text_color(t.muted).hover((s) => s.bg(t.hover).text_color(t.foreground))
          .on_click((_e, cx) => this.clickSub(recipe, sub, cx))
          .child(sub.name)))))
      .when(asking, (e) => e.child(v_flex().gap(4).px(8).pb(8)
        .child(Input.new(this.input).h(30).px(8).rounded(6).border_1().border_color(t.accent).bg(t.background).text_size(12).text_color(t.foreground))
        .when(Boolean(this.hint), (e) => e.child(div().truncate().text_size(11).text_color(t.dim).child(this.hint)))));
  }

  render(cx) {
    const t = theme();
    const key = JSON.stringify(shared("my.just"));
    if (key !== this.key) {
      this.key = key;
      this.groups = [];
      this.error = null;
      this.asking = null;
      this.refresh(cx);
    }
    const count = this.groups.reduce((n, [, recipes]) => n + recipes.length, 0);
    return v_flex().id("my-just").track_focus(this.handle)
      .on_key_down((e, cx) => {
        if (e.key === "escape" && this.asking) { this.asking = null; cx.stop_propagation(); cx.notify(); }
      })
      .size_full().min_h(0).rounded(10).overflow_hidden().bg(t.background)
      .border_1().border_color(t.border).text_color(t.foreground).text_size(13)
      .child(h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
        .child(div().font_semibold().child("Just"))
        .child(div().px(5).py(1).rounded(4).border_1().border_color(t.border).text_size(10).text_color(t.muted).child(`${count} recipes`))
        .child(div().flex_1())
        .child(div().id("just-refresh").size(22).flex().items_center().justify_center().rounded(5).cursor_pointer().text_color(t.dim)
          .hover((s) => s.bg(t.hover).text_color(t.foreground))
          .on_click((_e, cx) => { this.refresh(cx); cx.notify(); })
          .child(this.loading ? svg("mods/workspace-chrome/spinner.svg").size(14).text_color(t.accent).spin(900) : "↻")))
      .when(Boolean(this.error), (e) => e.child(div().px(14).py(10).text_color(t.ansi1).child(this.error)))
      .child(v_flex().id("just-list").flex_1().min_h(0).overflow_y_scrollbar().p(6)
        .children(this.groups.map(([group, recipes]) => v_flex().flex_none().pb(6)
          .when(Boolean(group), (e) => e.child(div().px(8).pt(4).pb(2).text_size(11).text_color(t.muted).child(group)))
          .children(recipes.map((recipe) => this.row(recipe, t)))))
        .when(!count && !this.error, (e) => e.child(div().p(8).text_color(t.dim).child(this.loading ? "Loading recipes…" : "No recipes"))));
  }
}
