import { defineConfig, devices } from "@playwright/test";
import path from "node:path";

const docsBuild = path.resolve(__dirname, "..", "build");

export default defineConfig({
  testDir: "./tests",
  outputDir: "./artifacts/test-results",
  fullyParallel: false,
  forbidOnly: true,
  retries: 0,
  workers: 1,
  timeout: 60_000,
  expect: {
    timeout: 8_000,
    toHaveScreenshot: {
      animations: "disabled",
      caret: "hide",
      scale: "css",
    },
  },
  reporter: [
    ["line"],
    ["html", { outputFolder: "./artifacts/report", open: "never" }],
  ],
  use: {
    baseURL: "http://127.0.0.1:4173",
    locale: "en-US",
    timezoneId: "UTC",
    reducedMotion: "reduce",
    serviceWorkers: "block",
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
  },
  webServer: {
    command: `python3 -m http.server 4173 --bind 127.0.0.1 --directory "${docsBuild}"`,
    url: "http://127.0.0.1:4173",
    reuseExistingServer: false,
    timeout: 30_000,
  },
  projects: [
    {
      name: "chromium",
      testIgnore: /visual\.spec\.ts/,
      use: { ...devices["Desktop Chrome"], browserName: "chromium" },
    },
    {
      name: "firefox",
      testIgnore: /visual\.spec\.ts/,
      use: { ...devices["Desktop Firefox"], browserName: "firefox" },
    },
    {
      name: "webkit",
      testIgnore: /visual\.spec\.ts/,
      use: { ...devices["Desktop Safari"], browserName: "webkit" },
    },
    {
      name: "chromium-visual",
      testMatch: /visual\.spec\.ts/,
      use: { ...devices["Desktop Chrome"], browserName: "chromium" },
    },
  ],
});
