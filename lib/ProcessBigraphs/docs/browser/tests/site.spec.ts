import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";
import fs from "node:fs";
import path from "node:path";

const repositoryRoot = path.resolve(__dirname, "..", "..", "..", "..", "..");
const contractPath = path.join(
  repositoryRoot,
  "spec",
  "process-bigraph-phase17-documentation-quality-v1.toml",
);
const contract = fs.readFileSync(contractPath, "utf8");
const sourcePaths = [...contract.matchAll(
  /^path = "lib\/ProcessBigraphs\/docs\/src\/(.+)\.md"$/gm,
)].map((match) => match[1]);
const curatedRoutes = sourcePaths.map((source) =>
  source === "index"
    ? "/"
    : source.endsWith("/index")
      ? `/${source.slice(0, -"/index".length)}/`
      : `/${source}/`
);

const viewports = [
  { id: "desktop", width: 1440, height: 900 },
  { id: "tablet", width: 1024, height: 768 },
  { id: "mobile", width: 390, height: 844 },
] as const;

const terminalRoutes = [
  "/",
  "/learn/first-multirate-composite/",
  "/case-studies/wortel-2021/",
  "/case-studies/merks-2006/",
  "/api/extension-experimental/",
] as const;

test.describe("all curated routes", () => {
  for (const route of curatedRoutes) {
    test(`${route} renders without accessibility or network defects`, async ({
      page,
    }) => {
      const consoleDefects: string[] = [];
      const requestDefects: string[] = [];
      page.on("request", (request) => {
        if (new URL(request.url()).origin !== "http://127.0.0.1:4173") {
          requestDefects.push(
            `external runtime request: ${request.method()} ${request.url()}`,
          );
        }
      });
      page.on("console", (message) => {
        if (message.type() === "error" || message.type() === "warning") {
          consoleDefects.push(`${message.type()}: ${message.text()}`);
        }
      });
      page.on("requestfailed", (request) => {
        if (new URL(request.url()).origin === "http://127.0.0.1:4173") {
          requestDefects.push(
            `${request.method()} ${request.url()}: ${
              request.failure()?.errorText ?? "unknown failure"
            }`,
          );
        }
      });
      page.on("response", (response) => {
        if (
          new URL(response.url()).origin === "http://127.0.0.1:4173" &&
          response.status() >= 400
        ) {
          requestDefects.push(
            `${response.request().method()} ${response.url()}: ${
              response.status()
            }`,
          );
        }
      });

      const response = await page.goto(route, { waitUntil: "networkidle" });
      expect(response?.ok(), `route ${route}`).toBeTruthy();
      await expect(page.locator("h1")).toBeVisible();
      await expect(page.locator(".pb-beta-banner")).toBeVisible();
      await expect(page).toHaveTitle(/ProcessBigraphs/);

      const accessibility = await new AxeBuilder({ page })
        .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
        .analyze();
      expect(accessibility.violations).toEqual([]);

      expect(consoleDefects).toEqual([]);
      expect(requestDefects).toEqual([]);
    });
  }
});

test.describe("terminal route matrix", () => {
  for (const viewport of viewports) {
    for (const colorScheme of ["light", "dark"] as const) {
      for (const route of terminalRoutes) {
        test(`${route} · ${viewport.id} · ${colorScheme}`, async ({ page }) => {
          await page.setViewportSize(viewport);
          await page.emulateMedia({
            colorScheme,
            reducedMotion: "reduce",
          });
          await page.goto(route, { waitUntil: "networkidle" });
          await page.evaluate(() => (document as any).fonts?.ready);

          const overflow = await page.evaluate(() => {
            const root = document.documentElement;
            return root.scrollWidth - root.clientWidth;
          });
          expect(overflow).toBeLessThanOrEqual(1);

          const article = page.locator("#documenter-page");
          await expect(article).toBeVisible();

          const images = article.locator("img");
          for (let index = 0; index < await images.count(); index += 1) {
            const image = images.nth(index);
            await expect(image).toHaveAttribute("alt", /.+/);
            expect(await image.evaluate(
              (element: HTMLImageElement) => element.complete &&
                element.naturalWidth > 0,
            )).toBeTruthy();
          }

          const codeBlocks = page.locator("pre");
          for (let index = 0; index < await codeBlocks.count(); index += 1) {
            const block = codeBlocks.nth(index);
            const overflowMode = await block.evaluate((element) =>
              getComputedStyle(element).overflowX
            );
            expect(["auto", "scroll"]).toContain(overflowMode);
          }

          const articleText = await article.innerText();
          expect(articleText).not.toContain(
            "ReferenceModels.Wortel2021.model(",
          );
          expect(articleText).not.toContain(
            "ReferenceModels.Merks2006.model(",
          );
        });
      }
    }
  }
});

test("complete source, navigation, copy control, and claim boundaries", async ({
  page,
}) => {
  await page.goto("/case-studies/wortel-2021/", {
    waitUntil: "networkidle",
  });
  await expect(page.getByRole("heading", {
    name: "Complete executed source",
    exact: true,
  })).toBeVisible();
  await expect(page.getByRole("heading", {
    name: "What this does not establish",
    exact: true,
  })).toBeVisible();
  await expect(page.getByText("51-parameter", { exact: false })).toBeVisible();
  await expect(page.locator("pre").first()).toContainText(
    "potts_model = PottsModel(",
  );
  await expect(page.locator("pre").first()).toContainText(
    "composite_model = PB.compose(",
  );
  await expect(page.locator("video")).toHaveAttribute(
    "aria-label",
    /Wortel/,
  );
  await expect(page.locator("video source")).toHaveAttribute(
    "src",
    /wortel-animation\.mp4$/,
  );

  const copyButton = page.locator(
    "button.docs-clipboard-button, button.copy-button",
  ).first();
  await expect(copyButton).toBeVisible();
  await copyButton.click();

  await page.goto("/case-studies/merks-2006/", {
    waitUntil: "networkidle",
  });
  await expect(page.getByText("500×500", { exact: false }).first()).toBeVisible();
  await expect(page.getByText("Figure 5", { exact: false }).first()).toBeVisible();
  await expect(page.locator("pre").first()).toContainText("LocalConnectivity()");
  await expect(page.locator("pre").first()).toContainText(
    "field_process = PB.managed_field_process(",
  );
  await expect(page.locator("video")).toHaveAttribute("aria-label", /Merks/);
  await expect(page.locator("video source")).toHaveAttribute(
    "src",
    /merks-animation\.mp4$/,
  );

  await page.goto("/examples/custom-engine-adapter/", {
    waitUntil: "networkidle",
  });
  await expect(page.locator("pre").first()).toContainText("stage_operation!");
  await expect(page.locator("pre").first()).toContainText("validate_candidate");
  await expect(page.locator("pre").first()).toContainText("publish_candidate!");
  await expect(page.locator("pre").first()).toContainText("discard_candidate!");
});

test("keyboard focus, skip link, and search dismissal", async ({
  page,
  browserName,
}) => {
  await page.goto("/", { waitUntil: "networkidle" });
  await page.keyboard.press(browserName === "webkit" ? "Alt+Tab" : "Tab");
  await expect(page.locator(".pb-skip-link")).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page.locator("#documenter-page")).toBeFocused();

  const trigger = page.locator("#documenter-search-query");
  await trigger.click();
  const search = page.locator("#pb-search-input");
  await expect(search).toBeFocused();
  await search.fill("checkpoint");
  await expect(page.locator("#pb-search-results a").first()).toBeVisible();
  await expect(page.locator("#pb-search-status")).toContainText("result");
  await page.keyboard.press("Escape");
  await expect(page.locator("#pb-search-modal")).toBeHidden();
  await expect(trigger).toBeFocused();
});

const journeys = [
  ["first-model", "/", "/learn/first-multirate-composite/", "multirate", ["Complete executed source", "Expected result"]],
  ["nested-composite", "/", "/examples/nested-composites/", "nested composite", ["mount", "schedule"]],
  ["extension-discovery", "/", "/api/extension-experimental/", "extension protocol", ["Experimental", "internal"]],
  ["minimal-adapter", "/api/extension-experimental/", "/examples/custom-engine-adapter/", "custom engine", ["stage_operation!", "discard_candidate!"]],
  ["checkpoint-restart", "/", "/learn/checkpoint-failure-replay/", "checkpoint restore", ["checkpoint", "restore"]],
  ["wortel-case", "/case-studies/", "/case-studies/wortel-2021/", "Wortel", ["reduced", "What this does not establish"]],
  ["merks-case", "/case-studies/", "/case-studies/merks-2006/", "Merks", ["500×500", "What this does not establish"]],
  ["status-and-migration", "/", "/concepts/capability-migration-troubleshooting/", "migration", ["internal beta", "migration"]],
] as const;

test.describe("registered persona journeys", () => {
  for (const [id, start, route, query, evidence] of journeys) {
    test(`journey:${id}`, async ({ page }) => {
      await page.goto(start, { waitUntil: "networkidle" });
      const searchTrigger = page.locator("#documenter-search-query");
      await searchTrigger.click();
      const search = page.locator("#pb-search-input");
      await search.fill(query);
      const result = page.locator(`#pb-search-results a[href*="${route}"]`).first();
      await expect(result).toBeVisible();
      await result.click();
      await page.waitForLoadState("networkidle");
      await expect(page).toHaveURL(new RegExp(route.replaceAll("/", "\\/")));
      const article = page.locator("#documenter-page");
      await expect(article).toBeVisible();
      for (const phrase of evidence) {
        await expect(article.getByText(phrase, { exact: false }).first()).toBeVisible();
      }
      await expect(page.locator(".docs-footer")).toBeVisible();
    });
  }
});

test("theme selection, persisted settings, next/previous navigation, and ARIA snapshots", async ({
  page,
}, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto("/", { waitUntil: "networkidle" });

  await page.locator("#documenter-settings-button").click();
  await page.locator("#documenter-themepicker").selectOption("documenter-dark");
  await expect(page.locator("html")).toHaveClass(/theme--documenter-dark/);
  await page.reload({ waitUntil: "networkidle" });
  await expect(page.locator("html")).toHaveClass(/theme--documenter-dark/);

  const next = page.locator(".docs-footer-nextpage");
  await expect(next).toHaveAttribute("href", /install-and-verify/);
  await next.click();
  await expect(page).toHaveURL(/install-and-verify/);
  const previous = page.locator(".docs-footer-prevpage");
  await expect(previous).toHaveAttribute("href", /(\.\.\/|\/)$/);

  for (const route of terminalRoutes) {
    await page.goto(route, { waitUntil: "networkidle" });
    const snapshot = await page.locator("#documenter").ariaSnapshot();
    expect(snapshot).toContain("heading");
    expect(snapshot).toContain("navigation");
    await testInfo.attach(
      `aria-${route === "/" ? "home" : route.replaceAll("/", "-")}.txt`,
      { body: snapshot, contentType: "text/plain" },
    );
  }
});
