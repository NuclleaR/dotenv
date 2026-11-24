// Right-side panel: the git worktrees of the focused terminal's repo, which the
// my-tabs mod shares as "my.git". The one that terminal is in is highlighted and
// cannot be deleted; any other linked worktree can, after a confirmation that says
// what goes with it. Its branch goes too only when merged, by its MR or PR or by git.
import { View, div, svg } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { exec, focused, home, notify, panes, run, shared, spaces, theme } from "herdr";
import {
  countChanges, currentWorktree, defaultBase, deleteDecision, mergeState, parseWorktrees, strayCommits,
} from "./git.js";
import { fetchMergeRequests } from "./forge.js";
import { openSpace, othersIn, spaceOf } from "./spaces.js";

const REFRESH_MS = 120000;
const FETCH_TIMEOUT = 30000;

// The focused terminal's folder: which worktree is the current one.
function focusedCwd() {
  const space = spaces().find((s) => s.active), f = focused();
  const pane = f?.pane ? panes().find((p) => p.pane === f.pane) : null;
  return pane?.cwd || f?.cwd || space?.folder || null;
}

function gitAt(cwd, on) {
  return async (args) => {
    const r = await exec("git", args, { cwd, on });
    return { ok: r.code === 0, out: r.stdout.trim(), err: r.stderr.trim() };
  };
}

async function must(git, args) {
  const r = await git(args);
  if (!r.ok) throw new Error(r.err || `git ${args[0]} failed`);
  return r.out;
}

// A copy of my-prs' runTool. mise activates in interactive shells only, and Herdr's
// PATH comes from the login shell, so a tool installed through mise has to be asked of mise.
async function runTool(tool, args) {
  try {
    return await exec(tool, args);
  } catch {
    const found = await exec("mise", ["which", tool]);
    if (found.code !== 0) throw new Error(`${tool} is not installed`);
    return exec(found.stdout.trim(), args);
  }
}

// Fresh origin/main for the git merge check. Runs every refresh, so it must never
// prompt: BatchMode makes ssh fail instead of asking for a passphrase or a host key.
async function fetchBase(common, on, base) {
  try {
    await exec("git", ["-c", "core.sshCommand=ssh -o BatchMode=yes", "fetch", "--quiet", "origin", base.slice("origin/".length)],
      { cwd: common, on, timeout: FETCH_TIMEOUT });
  } catch {}
}

async function homeOf(on) {
  if (!on) return home();
  return (await exec("sh", ["-c", 'printf %s "$HOME"'], { on })).stdout.trim();
}

const hasState = (wt) => Boolean(wt.branch) && !wt.main;
const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;
const message = (error) => error?.message ?? `${error}`;

export default class MyWorktrees extends View {
  init(_props, cx) {
    this.reset(null);
    this.loading = false;
    this.request = 0;
    // Path of the row whose check or delete is running.
    this.busy = null;
    cx.timer.every(REFRESH_MS, (cx) => { this.refresh(cx); cx.notify(); });
  }

  reset(repo) {
    this.repo = repo;
    this.worktrees = [];
    // Worktree path -> MergeState plus the `head` it was worked out for.
    this.states = new Map();
    // Worktree path -> uncommitted changes in it, for the row's chip.
    this.changes = new Map();
    // What the last refresh learned, to work out a state again for a moved branch.
    this.mrs = new Map();
    this.base = null;
    this.noun = null;
    // A refresh's problem (forge, git) and a delete's, kept apart so a refresh
    // does not wipe why a delete failed.
    this.error = null;
    this.actionError = null;
    this.note = null;
    // { path, changes, stray, others, space, spaceName, head, state, changed } while a row asks.
    this.confirm = null;
  }

  refresh(cx) {
    const repo = this.repo;
    if (!repo) return;
    const request = ++this.request;
    const fresh = () => request === this.request;
    this.loading = true;
    cx.spawn(async (cx) => {
      try {
        const git = gitAt(repo.common, repo.on);
        const list = parseWorktrees(await must(git, ["worktree", "list", "--porcelain"]));
        const homeDir = await homeOf(repo.on);
        if (!fresh()) return;
        // Rows first, their badges say "Checking…" until the slow part is done.
        this.worktrees = list;
        this.homeDir = homeDir;
        cx.notify();

        // One git status per worktree, side by side; a folder git cannot read counts as none.
        const counts = await Promise.all(list.map((wt) =>
          wt.prunable ? 0 : countChanges(gitAt(wt.path, repo.on)).catch(() => 0)));
        if (!fresh()) return;
        this.changes = new Map(list.map((wt, i) => [wt.path, counts[i]]));
        cx.notify();

        let base = await defaultBase(git);
        if (base) {
          await fetchBase(repo.common, repo.on, base);
          base = await defaultBase(git);
        }
        const rows = list.filter(hasState);
        let mrs = new Map(), forgeError = null;
        if (repo.forge) ({ mrs, error: forgeError } = await fetchMergeRequests(runTool, repo.forge, rows.map((wt) => wt.branch)));
        // "no MR found" only when the forge was actually asked.
        const noun = repo.forge && !forgeError ? (repo.forge.forge === "github" ? "PR" : "MR") : null;
        const states = new Map();
        for (const wt of rows) {
          states.set(wt.path, { ...await mergeState(git, wt, mrs.get(wt.branch), { base, forge: noun }), head: wt.head });
        }
        if (!fresh()) return;
        Object.assign(this, { states, mrs, base, noun, error: forgeError });
      } catch (error) {
        if (!fresh()) return;
        this.error = message(error);
      }
      this.loading = false;
      cx.notify();
    });
  }

  // How the worktree is right now, in the terms the confirmation speaks.
  async snapshot(wt, repo) {
    const at = gitAt(wt.path, repo.on);
    const space = spaceOf(wt.path, this.worktrees, repo.on) ?? null;
    return {
      changes: wt.prunable ? 0 : await countChanges(at),
      stray: wt.prunable || wt.branch ? 0 : await strayCommits(at),
      head: wt.prunable ? wt.head : await must(at, ["rev-parse", "--verify", "HEAD"]),
      space: space?.id ?? null,
      spaceName: space?.name ?? null,
      others: othersIn(wt.path, this.worktrees, repo.on, space?.id ?? null),
      current: wt.main || currentWorktree(this.worktrees, focusedCwd()) === wt.path,
    };
  }

  // The merge state for the branch as it is at `head`: the refresh's one while the
  // branch has not moved since, else worked out again, so a commit made after the
  // badge said "Merged" is never deleted with the branch.
  async stateFor(wt, head, repo) {
    if (!wt.branch) return null;
    const known = this.states.get(wt.path);
    if (known?.head === head) return known;
    const state = await mergeState(gitAt(repo.common, repo.on), { ...wt, head }, this.mrs.get(wt.branch),
      { base: this.base, forge: this.noun });
    return { ...state, head };
  }

  askDelete(wt, cx) {
    const repo = this.repo;
    if (this.busy || !repo) return;
    this.busy = wt.path;
    this.note = null;
    this.actionError = null;
    cx.spawn(async (cx) => {
      try {
        const now = await this.snapshot(wt, repo);
        const state = await this.stateFor(wt, now.head, repo);
        if (repo === this.repo && !now.current) this.confirm = { path: wt.path, ...now, state, changed: false };
      } catch (error) {
        this.actionError = message(error);
      }
      this.busy = null;
      cx.notify();
    });
  }

  remove(wt, cx) {
    const confirm = this.confirm, repo = this.repo;
    if (this.busy || !confirm || !repo) return;
    this.busy = wt.path;
    cx.spawn(async (cx) => {
      try {
        const now = await this.snapshot(wt, repo);
        const decision = deleteDecision(confirm, now);
        if (decision === "refuse") {
          this.confirm = null;
          this.actionError = `${wt.branch ?? wt.path} is the current worktree and cannot be deleted`;
        } else if (decision === "ask") {
          this.confirm = { path: wt.path, ...now, state: await this.stateFor(wt, now.head, repo), changed: true };
        } else {
          const git = gitAt(repo.common, repo.on);
          if (wt.prunable) await must(git, ["worktree", "prune"]);
          else await must(git, ["worktree", "remove", ...(decision === "force" ? ["--force"] : []), wt.path]);
          // Only once git has removed it: a refused removal must not kill the space's terminals.
          if (now.space) run("space.close", { id: now.space });
          this.confirm = null;
          // The head did not move since the confirmation, so its state still holds.
          if (wt.branch && confirm.state?.merged) {
            await must(git, ["branch", "-D", wt.branch]);
          } else if (wt.branch) {
            const reason = confirm.state?.reason ?? "its merge state was not known yet";
            this.note = `Kept ${wt.branch}: ${reason}`;
            notify({ title: `Kept ${wt.branch}`, body: reason, level: "info" });
          }
        }
      } catch (error) {
        this.actionError = message(error);
      }
      this.busy = null;
      if (repo === this.repo) this.refresh(cx);
      cx.notify();
    });
  }

  tilde(path) {
    const h = this.homeDir;
    return h && (path === h || path.startsWith(`${h}/`)) ? `~${path.slice(h.length)}` : path;
  }

  confirmLines(wt, confirm) {
    const lines = [];
    if (confirm.space) lines.push(`closes space "${confirm.spaceName}"`);
    if (confirm.others) lines.push(`${plural(confirm.others, "other terminal is", "other terminals are")} in it and will be left in a deleted folder`);
    if (confirm.changes) lines.push(`${plural(confirm.changes, "uncommitted change", "uncommitted changes")} will be lost`);
    if (confirm.stray) lines.push(`${plural(confirm.stray, "commit", "commits")} on no branch will be lost`);
    if (wt.prunable) lines.push("the folder is already gone");
    if (!wt.branch) lines.push("detached, there is no branch to delete");
    else if (confirm.state?.merged) lines.push("branch is merged and will be deleted");
    else lines.push(`branch is kept: ${confirm.state?.reason ?? "its merge state is not known yet"}`);
    return lines;
  }

  button(id, label, t, danger) {
    return div().id(id).px(6).py(2).rounded(5).border_1().border_color(t.border)
      .cursor_pointer().text_size(11).text_color(t.muted)
      .hover((s) => s.bg(t.hover).text_color(danger ? t.ansi1 : t.foreground))
      .child(label);
  }

  row(wt, current, t) {
    const isCurrent = wt.path === current;
    const state = this.states.get(wt.path);
    // git refuses a locked worktree even with one --force: the chip says why there is no button.
    const deletable = !wt.main && !isCurrent && !wt.locked;
    const confirm = deletable && this.confirm?.path === wt.path ? this.confirm : null;
    const kind = { ok: t.ansi2, warn: t.blocked, muted: t.dim };
    const chip = (text, color) => div().flex_none().px(4).rounded(4).border_1().border_color(t.border)
      .text_size(10).text_color(color).child(text);
    const space = spaceOf(wt.path, this.worktrees, this.repo.on);
    const changes = this.changes.get(wt.path) ?? 0;

    const head = v_flex().id(`wt-open-${wt.path}`).gap(3).min_w(0)
      .when(!wt.prunable, (e) => e.cursor_pointer().on_click(() => openSpace(wt.path, this.worktrees, this.repo.on)))
      .child(h_flex().gap(6).items_center().min_w(0)
        .child(div().flex_1().min_w(0).truncate().child(wt.branch ?? `detached ${wt.head.slice(0, 7)}`))
        .when(wt.main, (e) => e.child(chip("Main", t.muted)))
        .when(isCurrent, (e) => e.child(chip("Current", t.accent)))
        .when(Boolean(space), (e) => e.child(chip("space", t.muted)))
        .when(changes > 0, (e) => e.child(chip(plural(changes, "change", "changes"), t.blocked)))
        .when(wt.prunable, (e) => e.child(chip("Missing", t.ansi1)))
        .when(wt.locked, (e) => e.child(chip("Locked", t.blocked)))
        .when(Boolean(state), (e) => e.child(div().flex_none().text_size(11).text_color(kind[state.badge.kind]).child(state.badge.text)))
        .when(!state && hasState(wt), (e) => e.child(div().flex_none().text_size(11).text_color(t.dim).child("Checking…"))))
      .child(div().truncate().text_size(11).text_color(t.dim).child(this.tilde(wt.path)));

    // Side by side with `head`, not inside it: a click here must never open the space.
    const actions = this.busy === wt.path
      ? h_flex().gap(4).items_center()
        .child(svg("mods/workspace-chrome/spinner.svg").size(12).text_color(t.accent).spin(900))
        .child(div().text_size(11).text_color(t.dim).child(confirm ? "deleting…" : "checking…"))
      : confirm
        ? v_flex().gap(3).pt(2)
          .child(div().text_size(12).text_color(confirm.changed ? t.blocked : t.foreground)
            .child(confirm.changed ? "It changed since. Delete this worktree anyway?" : "Delete this worktree?"))
          .children(this.confirmLines(wt, confirm).map((line) => div().text_size(11).text_color(t.muted).child(`· ${line}`)))
          .child(h_flex().gap(4).pt(2)
            .child(this.button(`wt-cancel-${wt.path}`, "Cancel", t, false)
              .on_click((_e, cx) => { this.confirm = null; cx.notify(); }))
            .child(this.button(`wt-confirm-${wt.path}`, "Delete", t, true)
              .on_click((_e, cx) => { this.remove(wt, cx); cx.notify(); })))
        : null;

    return v_flex().id(`wt-${wt.path}`).flex_none().px(8).py(5).gap(3).rounded(7).border_1()
      .border_color(isCurrent ? t.accent : t.background)
      .hover((s) => s.bg(t.hover))
      .child(head)
      .when(Boolean(actions), (e) => e.child(actions))
      .when(!actions && deletable, (e) => e.child(h_flex()
        .child(this.button(`wt-delete-${wt.path}`, "delete", t, true)
          .on_click((_e, cx) => { this.askDelete(wt, cx); cx.notify(); }))));
  }

  render(cx) {
    const t = theme();
    const repo = shared("my.git") ?? null;
    const key = JSON.stringify(repo);
    if (key !== this.key) {
      this.key = key;
      this.reset(repo);
      this.refresh(cx);
    }
    const current = currentWorktree(this.worktrees, focusedCwd());
    const error = this.actionError || this.error;
    return v_flex().id("my-worktrees").size_full().min_h(0).rounded(10).overflow_hidden().bg(t.background)
      .border_1().border_color(t.border).text_color(t.foreground).text_size(13)
      .child(h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
        .child(div().font_semibold().child("Worktrees"))
        .child(div().px(5).py(1).rounded(4).border_1().border_color(t.border).text_size(10).text_color(t.muted)
          .child(`${this.worktrees.length}`))
        .child(div().flex_1())
        .child(div().id("worktrees-refresh").size(22).flex().items_center().justify_center().rounded(5).cursor_pointer().text_color(t.dim)
          .hover((s) => s.bg(t.hover).text_color(t.foreground))
          .on_click((_e, cx) => { this.actionError = null; this.note = null; this.refresh(cx); cx.notify(); })
          .child(this.loading ? svg("mods/workspace-chrome/spinner.svg").size(14).text_color(t.accent).spin(900) : "↻")))
      .when(Boolean(error), (e) => e.child(div().px(14).py(10).text_color(t.ansi1).child(error)))
      .when(Boolean(this.note), (e) => e.child(div().px(14).py(10).text_color(t.blocked).child(this.note)))
      .child(v_flex().id("worktrees-list").flex_1().min_h(0).overflow_y_scrollbar().p(6)
        .children(this.worktrees.map((wt) => this.row(wt, current, t)))
        .when(!this.worktrees.length && !error, (e) => e.child(div().p(8).text_color(t.dim)
          .child(this.loading ? "Loading worktrees…" : "No worktrees"))));
  }
}
