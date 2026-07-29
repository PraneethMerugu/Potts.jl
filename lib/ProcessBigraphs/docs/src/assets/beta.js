document.addEventListener("DOMContentLoaded", () => {
  if (!document.querySelector(".pb-beta-banner")) {
    const banner = document.createElement("div");
    banner.className = "pb-beta-banner";
    banner.setAttribute("role", "status");
    const migration = new URL(
      "concepts/capability-migration-troubleshooting/",
      new URL(`${documenterBaseURL.replace(/\/?$/, "/")}`, window.location.href),
    ).pathname;
    banner.innerHTML =
      'Qualified unpublished internal beta · APIs may change through explicit migration · ' +
      `<a href="${migration}">status and migration</a>`;
    document.body.prepend(banner);
    document.body.classList.add("pb-beta-visible");
  }

  document
    .querySelectorAll(".content pre, .content code.nohighlight")
    .forEach((region) => {
      if (region.scrollWidth > region.clientWidth) {
        region.setAttribute("tabindex", "0");
        region.setAttribute("aria-label", "Scrollable code output");
      }
    });
});
