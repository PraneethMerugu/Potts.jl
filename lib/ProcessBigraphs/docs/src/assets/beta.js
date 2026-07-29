document.addEventListener("DOMContentLoaded", () => {
  if (document.querySelector(".pb-beta-banner")) return;
  const banner = document.createElement("div");
  banner.className = "pb-beta-banner";
  banner.setAttribute("role", "status");
  banner.innerHTML =
    'Qualified unpublished internal beta · APIs may change through explicit migration · ' +
    '<a href="/Potts.jl/ProcessBigraphs/dev/concepts/capability-migration-troubleshooting/">status and migration</a>';
  document.body.prepend(banner);
  document.body.classList.add("pb-beta-visible");
});
