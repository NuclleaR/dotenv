// Which of my tab-bar buttons are on in the shown space, as the Panels popup (mod
// my-panels) stored them in shared "my.panels". switches.js is that mod's own
// file, copied in by common/herdr.sh, so both read the store the same way.
// Herdr's Files and Changes stay with its "workspace.panels".
import { shared, spaces } from "herdr";
import { SWITCHES, isOn } from "./switches.js";

// The side panels among the switches; VS Code is a button only.
const MY_PANELS = SWITCHES.map((s) => s.id).filter((id) => id !== "vscode");

export function panelOn(id) {
  const space = spaces().find((s) => s.active);
  return isOn(shared("my.panels"), space?.id ?? null, id);
}

// Mine that are on here: with Herdr's, the panels that may be shown and restored.
export function myPanels() {
  return MY_PANELS.filter(panelOn);
}
