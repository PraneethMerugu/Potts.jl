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
  source === "index" ? "/" : `/${source}/`
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

          const images = page.locator("main img");
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

          expect(await page.locator("main").innerText()).not.toContain(
            "ReferenceModels.Wortel2021.model(",
          );
          expect(await page.locator("main").innerText()).not.toContain(
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
  await expect(page.getByText("Complete executed source")).toBeVisible();
  await expect(page.getByText("What this does not establish")).toBeVisible();
  await expect(page.getByText("51-parameter", { exact: false })).toBeVisible();
  await expect(page.locator("pre").first()).toContainText(
    "potts_model = PottsModel(",
  );
  await expect(page.locator("pre").first()).toContainText(
    "composite_model = PB.compose(",
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

  await page.goto("/examples/custom-engine-adapter/", {
    waitUntil: "networkidle",
  });
  await expect(page.locator("pre").first()).toContainText("stage_operation!");
  await expect(page.locator("pre").first()).toContainText("validate_candidate");
  await expect(page.locator("pre").first()).toContainText("publish_candidate!");
  await expect(page.locator("pre").first()).toContainText("discard_candidate!");
});

test("keyboard focus, skip link, and search dismissal", async ({ page }) => {
  await page.goto("/", { waitUntil: "networkidle" });
  await page.keyboard.press("Tab");
  const focused = page.locator(":focus");
  await expect(focused).toBeVisible();

  const search = page.locator(
    "input#documenter-search-query, input[aria-label*='Search']",
  ).first();
  if (await search.count()) {
    await search.focus();
    await search.fill("checkpoint");
    await page.keyboard.press("Escape");
    await expect(search).toBeVisible();
  }
});
