# Herdr panel switches — design

Date: 2026-11-24

## Intent

The Herdr tab bar shows a button per side panel plus VS Code. Not every space
wants all of them: one needs no Docker, another no Worktrees. Switches turn my
buttons on or off per space, over a default, without editing the layout.

## Decided with the user

- **What**: only my buttons — MRs/PRs, Worktrees, Just, Docker, VS Code.
  Herdr's own Files and Changes are not touched; they stay with its
  `workspace.panels`.
- **Where**: a sliders button at the end of the tab bar opens a popup.
- **Scope**: per Herdr space, over a global default. A space follows the default
  until a switch is changed there.

## How it works

- The popup has two tabs: "This space" (the shown space) and "Default" (every
  space that did not choose otherwise). Without a shown space only Default is
  there.
- The store is shared `my.panels`:
  `{ default: { <id>: false }, spaces: { <space id>: { <id>: boolean } } }`.
  Missing means on. A space keeps only the switches that differ from the
  default: switching one back to the default's value drops it, so a later change
  of the default reaches it. A dot marks a switch the space chose itself, and
  "Reset this space to default" drops all of them.
- Spaces are keyed by Herdr's space id: a newly opened space, even for the same
  repo, starts on the default. Entries of closed spaces stay in the store.
- The layout keeps every panel block; only the buttons come and go. The
  automatic rules stay on top: MRs/PRs only in a GitLab or GitHub repo,
  Worktrees only in a git repo, Just only with a justfile.
- A panel switched off while open is hidden, and is not restored when switching
  to that space.
- Shared values are persisted and every mod re-renders when one changes, so a
  switch applies at once.

## Parts

- `herdr/mods/my-panels/` — the popup (`mod.json` `overlay` popup, opened with
  `mod.open:my-panels`, which keys.json can also bind). `switches.js` holds the
  list and the store logic, Herdr-free, so `node --test` covers it.
- `herdr/patches/my-tabs/panels.js` — `panelOn(id)` and `myPanels()` for the
  shown space, reading the store through a copy of `switches.js` that
  `common/herdr.sh` puts into the clone. `button.js` wraps each of my buttons in
  `panelOn` and adds the sliders button; `render-start.js` hides a panel that was
  switched off while open.
- `herdr/patches/my-tabs/sliders.svg` — the button's icon.
- `common/herdr.sh` — imports `panels.js`, builds `enabled` as
  `[...workspace.panels, ...myPanels()]`, copies the new files.
