// Which of my tab-bar buttons are on, per Herdr space, over a default. Imports
// nothing from Herdr, so plain `node --test` can run it; common/herdr.sh also
// copies it into the my-tabs clone, so the popup and the tab bar read one logic.
//
// Herdr's own Files and Changes are not here: they stay with its
// "workspace.panels". The store is shared "my.panels":
//   { default: { <id>: false, … }, spaces: { <space id>: { <id>: boolean, … } } }
// A space holds only the switches that differ from the default, so a changed
// default reaches every space that never chose otherwise. Missing means on.

export const SWITCHES = [
  { id: "merge-requests", label: "MRs / PRs" },
  { id: "worktrees", label: "Worktrees" },
  { id: "just", label: "Just" },
  { id: "docker", label: "Docker" },
  { id: "vscode", label: "VS Code" },
];

const object = (value) => (value && typeof value === "object" && !Array.isArray(value) ? value : {});

function parts(store) {
  const s = object(store);
  return { defaults: object(s.default), spaces: object(s.spaces) };
}

const defaultOn = (defaults, id) => defaults[id] !== false;

export function isOn(store, spaceId, id) {
  const { defaults, spaces } = parts(store);
  const own = spaceId ? object(spaces[spaceId])[id] : undefined;
  return typeof own === "boolean" ? own : defaultOn(defaults, id);
}

/** Whether the space chose this switch itself rather than following the default. */
export function overridden(store, spaceId, id) {
  const { spaces } = parts(store);
  return Boolean(spaceId) && typeof object(spaces[spaceId])[id] === "boolean";
}

/** A new store with one switch set, in `scope`: "default" or a space id. */
export function setSwitch(store, scope, id, on) {
  const { defaults, spaces } = parts(store);
  if (scope === "default") {
    const { [id]: _, ...rest } = defaults;
    return { default: on ? rest : { ...rest, [id]: false }, spaces };
  }
  const { [id]: _, ...rest } = object(spaces[scope]);
  const own = on === defaultOn(defaults, id) ? rest : { ...rest, [id]: on };
  const { [scope]: __, ...others } = spaces;
  return { default: defaults, spaces: Object.keys(own).length ? { ...others, [scope]: own } : others };
}

/** A new store where the space follows the default for every switch again. */
export function resetSpace(store, spaceId) {
  const { defaults, spaces } = parts(store);
  const { [spaceId]: _, ...others } = spaces;
  return { default: defaults, spaces: others };
}
