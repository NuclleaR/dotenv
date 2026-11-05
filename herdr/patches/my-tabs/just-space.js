// The folder of the justfile at or above the focused terminal's folder. The tabs
// mod asks on every render and hands the answer to my-just as shared "my.just".
import { exec, setShared } from "herdr";
import { location } from "./repo-space.js";

// Walks up by hand: `just` itself may not be on this exec's PATH.
const FIND_JUSTFILE = `dir=$PWD
while :; do
  for name in justfile Justfile .justfile; do
    [ -f "$dir/$name" ] && { echo "$dir"; exit 0; }
  done
  [ -z "$dir" ] || [ "$dir" = / ] && exit 1
  dir=\${dir%/*}
done`;

const answers = new Map();
let published;

function publish(just) {
  const value = JSON.stringify(just);
  if (value === published) return;
  published = value;
  setShared("my.just", just);
}

// { root, on }, null when there is no justfile, undefined while first asked.
export function justSpace(cx) {
  const { cwd, on } = location();
  if (!cwd) return null;
  const key = JSON.stringify([cwd, on]);
  if (!answers.has(key)) {
    answers.set(key, undefined);
    cx.spawn(async (cx) => {
      try {
        const r = await exec("sh", ["-c", FIND_JUSTFILE], { cwd, on });
        answers.set(key, r.code === 0 ? { root: r.stdout.trim(), on } : null);
        cx.notify();
      } catch {
        // Machine offline or folder gone: forget it so a later render asks again.
        answers.delete(key);
      }
    });
  }
  const just = answers.get(key);
  if (just) publish(just);
  return just;
}
