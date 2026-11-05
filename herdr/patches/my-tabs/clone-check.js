// Tells once per run if Herdr's own files changed since the clones were built. It
// compares the files themselves: a build from source can change without a version.
import { appHome, notify, readTextFile } from "herdr";

const BUILT_FROM = [
  ["mods/tabs/main.js", "mods/my-tabs/shipped/tabs-main.txt"],
  ["layouts/main.json", "mods/my-tabs/shipped/main-layout.txt"],
];

let checked = false;

export function checkClones(cx) {
  if (checked) return;
  checked = true;
  cx.spawn(async () => {
    for (const [shipped, copy] of BUILT_FROM) {
      const [now, then] = await Promise.all([
        readTextFile(`${appHome()}/${shipped}`),
        readTextFile(`${appHome()}/${copy}`),
      ]);
      if (now !== null && then !== null && now === then) continue;
      notify({
        title: "Herdr changed, clones are stale",
        body: "Run dotenv's common/herdr.sh",
        level: "warning",
      });
      return;
    }
  });
}
