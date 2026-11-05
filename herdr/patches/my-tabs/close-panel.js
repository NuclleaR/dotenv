    const repo = repoSpace(cx);
    if (repo === null && panel && !panel.hidden && body?.active === "merge-requests") run("layout.hide", { id: "panel" });
