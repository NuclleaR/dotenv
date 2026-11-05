    checkClones(cx);
    const repo = repoSpace(cx), justfile = justSpace(cx);
    if (repo === null && panel && !panel.hidden && body?.active === "merge-requests") run("layout.hide", { id: "panel" });
    if (justfile === null && panel && !panel.hidden && body?.active === "just") run("layout.hide", { id: "panel" });
