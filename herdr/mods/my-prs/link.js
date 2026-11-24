// Ctrl+click on a link in a terminal: a host listed in my-links.json opens in the
// browser its rule names; everything else is passed on to Herdr, which opens it in
// the system's default browser. Herdr offers a click only when it matches a rule in
// this mod's mod.json "link_handlers" (every http(s) URL: the hosts are per machine,
// in my-links.json); the layout's "link_handlers": ["my-prs"] sets the order.
import { notify } from "herdr";
import { browserCommand, launch } from "./open-link.js";

export async function handleLink(click) {
  if (click.link.kind !== "url") return "pass";
  const command = await browserCommand(click.link.url);
  if (!command) return "pass";
  try {
    await launch(command, click.link.url);
    return "handled";
  } catch (error) {
    notify({ title: `Could not start ${command[0]}`, body: `${error.message}. Opening it in the default browser.`, level: "warning" });
    return "pass";
  }
}
