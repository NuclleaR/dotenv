    checkClones(cx);
    const repo = repoSpace(cx), justfile = justSpace(cx);
    if (repo === null && panel && !panel.hidden && body?.active === "merge-requests") run("layout.hide", { id: "panel" });
    if (justfile === null && panel && !panel.hidden && body?.active === "just") run("layout.hide", { id: "panel" });
    const git = gitSpace(cx, repo);
    if (git === null && panel && !panel.hidden && body?.active === "worktrees") run("layout.hide", { id: "panel" });
    // Switched off in the Panels popup while open.
    if (panel && !panel.hidden && body?.active && !enabled.includes(body.active)) run("layout.hide", { id: "panel" });
