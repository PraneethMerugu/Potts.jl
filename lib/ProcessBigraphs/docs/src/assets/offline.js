(() => {
  "use strict";

  const onReady = (callback) => {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", callback, { once: true });
    } else {
      callback();
    }
  };

  const baseURL = () =>
    new URL(
      `${documenterBaseURL.replace(/\/?$/, "/")}`,
      window.location.href,
    );

  const closeModal = (modal) => {
    modal?.classList.remove("is-active");
    modal?.setAttribute("aria-hidden", "true");
  };

  function installSkipLink() {
    const main = document.querySelector("main, #documenter-page");
    if (!main) return;
    if (!main.id) main.id = "documenter-page";
    main.setAttribute("tabindex", "-1");
    const link = document.createElement("a");
    link.className = "pb-skip-link";
    link.href = `#${main.id}`;
    link.textContent = "Skip to main content";
    document.body.prepend(link);
  }

  function installCopyButtons() {
    document.querySelectorAll("pre").forEach((block) => {
      if (block.querySelector(".copy-button")) return;
      const button = document.createElement("button");
      button.type = "button";
      button.className = "copy-button";
      button.setAttribute("aria-label", "Copy this code block");
      button.title = "Copy this code block";
      button.textContent = "Copy";
      button.addEventListener("click", async () => {
        const code = block.querySelector("code");
        const text = code?.innerText ?? block.innerText;
        try {
          await navigator.clipboard.writeText(text);
          button.textContent = "Copied";
          button.classList.add("success");
        } catch {
          const field = document.createElement("textarea");
          field.value = text;
          field.style.position = "fixed";
          field.style.opacity = "0";
          document.body.append(field);
          field.select();
          document.execCommand("copy");
          field.remove();
          button.textContent = "Copied";
          button.classList.add("success");
        }
        window.setTimeout(() => {
          button.textContent = "Copy";
          button.classList.remove("success");
        }, 1500);
      });
      block.append(button);
    });
  }

  function installSidebar() {
    const sidebar = document.querySelector("#documenter > .docs-sidebar");
    const button = document.querySelector("#documenter-sidebar-button");
    if (!sidebar || !button) return;
    button.setAttribute("aria-label", "Toggle documentation navigation");
    button.setAttribute("aria-controls", "documenter-sidebar");
    sidebar.id = "documenter-sidebar";
    button.addEventListener("click", (event) => {
      event.preventDefault();
      const visible = sidebar.classList.toggle("visible");
      button.setAttribute("aria-expanded", String(visible));
    });
    document.querySelector("#documenter > .docs-main")?.addEventListener(
      "click",
      (event) => {
        if (event.target !== button) {
          sidebar.classList.remove("visible");
          button.setAttribute("aria-expanded", "false");
        }
      },
    );
  }

  function installSettings() {
    const modal = document.querySelector("#documenter-settings");
    const button = document.querySelector("#documenter-settings-button");
    if (!modal || !button) return;
    modal.setAttribute("role", "dialog");
    modal.setAttribute("aria-modal", "true");
    modal.setAttribute("aria-label", "Documentation settings");
    modal.setAttribute("aria-hidden", "true");
    button.setAttribute("aria-label", "Open documentation settings");
    button.addEventListener("click", (event) => {
      event.preventDefault();
      const active = modal.classList.toggle("is-active");
      modal.setAttribute("aria-hidden", String(!active));
      if (active) modal.querySelector("select, button")?.focus();
    });
    modal.querySelector("button.delete")?.setAttribute(
      "aria-label",
      "Close documentation settings",
    );
    modal.querySelector("button.delete")?.addEventListener(
      "click",
      () => closeModal(modal),
    );
    modal.querySelector(".modal-background")?.addEventListener(
      "click",
      () => closeModal(modal),
    );

    const picker = modal.querySelector("#documenter-themepicker");
    if (picker) {
      const selected = window.localStorage?.getItem("documenter-theme");
      if (selected) picker.value = selected;
      picker.addEventListener("change", () => {
        if (picker.value === "auto") {
          window.localStorage?.removeItem("documenter-theme");
        } else {
          window.localStorage?.setItem("documenter-theme", picker.value);
        }
        set_theme_from_local_storage();
      });
    }
  }

  function installSearch() {
    const trigger = document.querySelector("#documenter-search-query");
    if (!trigger) return;
    trigger.setAttribute("aria-label", "Search ProcessBigraphs documentation");
    trigger.setAttribute("aria-haspopup", "dialog");

    const modal = document.createElement("div");
    modal.id = "pb-search-modal";
    modal.className = "pb-search-modal";
    modal.hidden = true;
    modal.innerHTML = `
      <div class="pb-search-backdrop"></div>
      <section class="pb-search-card" role="dialog" aria-modal="true"
               aria-labelledby="pb-search-title">
        <header>
          <h2 id="pb-search-title">Search ProcessBigraphs.jl</h2>
          <button type="button" class="pb-search-close"
                  aria-label="Close search">Close</button>
        </header>
        <label for="pb-search-input">Search terms</label>
        <input id="pb-search-input" type="search" autocomplete="off"
               placeholder="Try checkpoint, adapter, or migration">
        <p id="pb-search-status" role="status" aria-live="polite"></p>
        <ol id="pb-search-results"></ol>
      </section>`;
    document.body.append(modal);

    const input = modal.querySelector("#pb-search-input");
    const status = modal.querySelector("#pb-search-status");
    const results = modal.querySelector("#pb-search-results");
    const entries = () => globalThis.documenterSearchIndex?.docs ?? [];

    const close = () => {
      modal.hidden = true;
      trigger.focus();
    };
    const open = () => {
      modal.hidden = false;
      input.focus();
      input.select();
    };
    const render = () => {
      const query = input.value.trim().toLocaleLowerCase("en-US");
      results.replaceChildren();
      if (query.length < 2) {
        status.textContent = "Enter at least two characters.";
        return;
      }
      const terms = query.split(/\s+/);
      const matches = entries()
        .map((entry) => {
          const title = String(entry.title ?? "");
          const text = String(entry.text ?? "");
          const haystack = `${title}\n${text}`.toLocaleLowerCase("en-US");
          const score = terms.reduce(
            (total, term) =>
              total +
              (title.toLocaleLowerCase("en-US").includes(term) ? 4 : 0) +
              (haystack.includes(term) ? 1 : 0),
            0,
          );
          return { entry, score };
        })
        .filter(({ score }) => score >= terms.length)
        .sort((left, right) =>
          right.score - left.score ||
          String(left.entry.title).localeCompare(String(right.entry.title))
        )
        .slice(0, 30);

      status.textContent = `${matches.length} result${
        matches.length === 1 ? "" : "s"
      } shown.`;
      for (const { entry } of matches) {
        const item = document.createElement("li");
        const link = document.createElement("a");
        link.href = new URL(entry.location, baseURL()).href;
        link.textContent = entry.title;
        const context = document.createElement("p");
        context.textContent = String(entry.text ?? "").slice(0, 180);
        item.append(link, context);
        results.append(item);
      }
    };

    trigger.addEventListener("click", open);
    modal.querySelector(".pb-search-close").addEventListener("click", close);
    modal.querySelector(".pb-search-backdrop").addEventListener("click", close);
    input.addEventListener("input", render);
    document.addEventListener("keydown", (event) => {
      if ((event.ctrlKey || event.metaKey) && event.key === "/") {
        event.preventDefault();
        open();
      } else if (event.key === "Escape" && !modal.hidden) {
        event.preventDefault();
        close();
      }
    });
  }

  function installArticleToggle() {
    const button = document.querySelector("#documenter-article-toggle-button");
    if (!button) return;
    button.setAttribute("aria-label", "Toggle all API details");
    button.addEventListener("click", (event) => {
      event.preventDefault();
      const details = [...document.querySelectorAll("details.docstring")];
      const shouldOpen = details.some((item) => !item.open);
      details.forEach((item) => {
        item.open = shouldOpen;
      });
      button.setAttribute("aria-expanded", String(shouldOpen));
    });
  }

  function repairDocstringSummaries() {
    document
      .querySelectorAll("summary > a.docstring-binding")
      .forEach((link) => {
        const label = document.createElement("span");
        label.className = link.className;
        label.append(...link.childNodes);
        link.replaceWith(label);
      });
  }

  onReady(() => {
    installSkipLink();
    installCopyButtons();
    installSidebar();
    installSettings();
    installSearch();
    installArticleToggle();
    repairDocstringSummaries();
  });
})();
