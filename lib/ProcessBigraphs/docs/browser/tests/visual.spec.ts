import { test, expect } from "@playwright/test";

const routes = [
  { id: "home", path: "/" },
  { id: "first-multirate-composite", path: "/learn/first-multirate-composite/" },
  { id: "examples", path: "/examples/" },
  { id: "wortel-2021", path: "/case-studies/wortel-2021/" },
  { id: "merks-2006", path: "/case-studies/merks-2006/" },
  { id: "extension-experimental-api", path: "/api/extension-experimental/" },
] as const;

test.describe("pinned Chromium visual regression", () => {
  test.skip(({ browserName }) => browserName !== "chromium");

  for (const route of routes) {
    test(route.id, async ({ page }) => {
      await page.setViewportSize({ width: 1440, height: 900 });
      await page.emulateMedia({ colorScheme: "light", reducedMotion: "reduce" });
      await page.goto(route.path, { waitUntil: "networkidle" });
      await page.evaluate(() => (document as any).fonts?.ready);
      await expect(page.locator("#documenter-page")).toBeVisible();
      await expect(page).toHaveScreenshot(`${route.id}.png`, {
        animations: "disabled",
        fullPage: true,
        maxDiffPixelRatio: 0.001,
      });
    });
  }
});
