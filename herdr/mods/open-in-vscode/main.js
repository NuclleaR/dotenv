// Opens the focused terminal's folder in VS Code, then closes itself.
// Started with `mod.open:open-in-vscode`; it has no UI of its own.
import { View, div } from "gpui-kit";
import { closeOverlay, exec, focused, notify, props, spaces } from "herdr";

function fail(title, body) {
  notify({ title, body, level: "error" });
}

async function openFocusedFolder() {
  const now = focused();
  const space = spaces().find((s) => s.id === now?.space);
  // A focused mod pane has no cwd, so fall back to the space's folder.
  const folder = now?.cwd || space?.folder;
  if (!folder) {
    fail("Open in VS Code", "The focused pane has no folder.");
    return;
  }

  // A remote path only exists on its machine, so VS Code must connect there.
  const args = space?.machine
    ? ["--remote", `ssh-remote+${space.machine}`, folder]
    : [folder];

  try {
    const result = await exec("code", args);
    if (result.code !== 0) {
      fail("VS Code could not open the folder", result.stderr.trim() || folder);
    }
  } catch (error) {
    fail("Could not start VS Code", `${error}`);
  }
}

export default class OpenInVscode extends View {
  init(_props, cx) {
    const overlay = props()?.overlay;
    // Only act when opened on request, not when loaded by `herdr-app check`.
    if (!overlay) return;
    cx.spawn(async () => {
      await openFocusedFolder();
      closeOverlay(overlay);
    });
  }

  render() {
    return div();
  }
}
