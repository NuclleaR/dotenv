// Which browser a link's host goes to, from ~/.config/herdr-app/my-links.json.
// Imports nothing from Herdr, so plain `node --test` can run it.
//
//   { "rules": [ { "hosts": ["gitlab.example.com", "*.atlassian.net"], "open": ["brave"] } ] }
//
// The first rule whose hosts match wins; "*.x" matches every subdomain of x, not x
// itself. `open` is the command, its arguments, then the URL. No match: null, and
// the link goes to the system's default browser.

/** @typedef {{ hosts: string[], open: string[] }} Rule */

/** The host of an http(s) link, lowercased; null for anything else. */
export function hostOf(url) {
  const match = /^https?:\/\/(?:[^@/?#]*@)?([^:/?#]+)/i.exec(url);
  return match ? match[1].toLowerCase() : null;
}

function matches(pattern, host) {
  return pattern.startsWith("*.") ? host.endsWith(pattern.slice(1)) : host === pattern;
}

/** @param {Rule[]} rules @returns {string[] | null} the command to open it with */
export function browserFor(rules, url) {
  const host = hostOf(url);
  if (!host) return null;
  return rules.find((rule) => rule.hosts.some((pattern) => matches(pattern, host)))?.open ?? null;
}

// Exit 127 when the browser is not installed; otherwise start it in the background
// and return at once. A browser that was not running yet stays up as the started
// process, and Herdr's exec would wait for it and kill it at its timeout.
const LAUNCH = 'command -v "$1" >/dev/null 2>&1 || exit 127; "$@" </dev/null >/dev/null 2>&1 &';

/** Arguments for `sh` that open `url` with `command`; the URL never passes through the shell's parser. */
export function launchArgs(command, url) {
  return ["-c", LAUNCH, "sh", ...command, url];
}

const strings = (value) => Array.isArray(value) && value.every((v) => typeof v === "string" && v.trim());

/**
 * The usable rules of the file's text (null: no file). A broken file gives no
 * rules; a broken rule is skipped and named, so one typo does not stop the rest.
 * @returns {{ rules: Rule[], error: string | null }}
 */
export function parseRules(text) {
  if (text === null || !text.trim()) return { rules: [], error: null };
  let config;
  try {
    config = JSON.parse(text);
  } catch (error) {
    return { rules: [], error: `my-links.json: ${error.message}` };
  }
  if (!config || !Array.isArray(config.rules)) return { rules: [], error: 'my-links.json: expected { "rules": [ … ] }' };
  const rules = [], skipped = [];
  config.rules.forEach((rule, i) => {
    if (rule && strings(rule.hosts) && strings(rule.open) && rule.open.length) {
      rules.push({ hosts: rule.hosts.map((h) => h.trim().toLowerCase()), open: rule.open });
    } else {
      skipped.push(`rule ${i + 1}`);
    }
  });
  const error = skipped.length
    ? `my-links.json: ${skipped.join(", ")} ignored, each needs "hosts" and "open" as lists of strings`
    : null;
  return { rules, error };
}
