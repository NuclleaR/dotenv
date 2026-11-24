// Opening a link in the browser my-links.json picks for its host, else in the
// system's default one. Used by link.js for Ctrl+click in terminals and by this
// panel's ↗ button. It lives in this mod because Herdr refuses an import from
// another mod's folder. Browsers start on this computer, also for a terminal on
// another machine.
import { appHome, exec, notify, readTextFile, window } from "herdr";
import { browserFor, launchArgs, parseRules } from "./link-rules.js";

let reported = null;

// Read on every click, so an edit to the file applies at once. A problem with it
// is told once, not on every click.
async function rules() {
  let text = null;
  try {
    text = await readTextFile(`${appHome()}/my-links.json`);
  } catch {}
  const { rules, error } = parseRules(text);
  if (error && error !== reported) notify({ title: "Link rules", body: error, level: "warning" });
  reported = error;
  return rules;
}

/** The browser command my-links.json gives this URL, null for the system's default. */
export async function browserCommand(url) {
  return browserFor(await rules(), url);
}

/** Starts it in the background; throws when it is not installed or did not start. */
export async function launch(command, url) {
  const r = await exec("sh", launchArgs(command, url));
  if (r.code === 127) throw new Error(`${command[0]} is not installed`);
  if (r.code !== 0) throw new Error(r.stderr.trim() || `${command[0]} exited with ${r.code}`);
}

/** For a panel's button: the configured browser, else (or when it fails) the default one. */
export async function openUrl(url) {
  const command = await browserCommand(url);
  if (command) {
    try {
      await launch(command, url);
      return;
    } catch (error) {
      notify({ title: `Could not start ${command[0]}`, body: `${error.message}. Opening it in the default browser.`, level: "warning" });
    }
  }
  const opener = window()?.platform === "macos" ? "open" : "xdg-open";
  try {
    await exec(opener, [url]);
  } catch (error) {
    notify({ title: "Could not open the link", body: `${error}`, level: "error" });
  }
}
