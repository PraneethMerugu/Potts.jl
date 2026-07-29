import { createServer } from "node:http";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import handler from "serve-handler";
import lighthouse from "lighthouse";
import { launch } from "chrome-launcher";
import { chromium } from "@playwright/test";

const root = path.resolve(import.meta.dirname, "..", "..", "build");
const output = path.resolve(import.meta.dirname, "..", "artifacts", "lighthouse");
const allRoutes = [
  ["home", "/"],
  ["first-multirate-composite", "/learn/first-multirate-composite/"],
  ["wortel-2021", "/case-studies/wortel-2021/"],
  ["merks-2006", "/case-studies/merks-2006/"],
  ["extension-experimental-api", "/api/extension-experimental/"],
];
const requestedRoute = process.env.LIGHTHOUSE_ROUTE;
const routes = requestedRoute
  ? allRoutes.filter(([id]) => id === requestedRoute)
  : allRoutes;
if (routes.length === 0) throw new Error(`unknown LIGHTHOUSE_ROUTE: ${requestedRoute}`);
const thresholds = {
  accessibility: 1,
  "best-practices": 1,
  seo: 0.93,
  performance: 0.90,
};

fs.rmSync(output, { recursive: true, force: true });
fs.mkdirSync(output, { recursive: true });
const server = createServer((request, response) =>
  handler(request, response, { public: root, directoryListing: false })
);
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const address = server.address();
if (!address || typeof address === "string") throw new Error("server did not bind");

const chrome = await launch({
  chromePath: chromium.executablePath(),
  chromeFlags: [
    "--headless",
    "--no-sandbox",
    "--disable-dev-shm-usage",
    "--disable-gpu",
    "--window-size=390,844",
  ],
});

const results = {};
let failed = false;
try {
  for (const [id, route] of routes) {
    const runs = [];
    for (let index = 1; index <= 3; index += 1) {
      const result = await lighthouse(
        `http://127.0.0.1:${address.port}${route}`,
        {
          port: chrome.port,
          output: ["json", "html"],
          logLevel: "error",
          formFactor: "mobile",
          screenEmulation: {
            mobile: true,
            width: 390,
            height: 844,
            deviceScaleFactor: 1,
            disabled: false,
          },
          throttlingMethod: "provided",
          onlyCategories: Object.keys(thresholds),
        },
      );
      if (!result) throw new Error(`Lighthouse returned no result for ${route}`);
      const [json, html] = result.report;
      fs.writeFileSync(path.join(output, `${id}-${index}.json`), json);
      fs.writeFileSync(path.join(output, `${id}-${index}.html`), html);
      const scores = Object.fromEntries(
        Object.keys(thresholds).map((key) => [key, result.lhr.categories[key].score]),
      );
      scores.cls = result.lhr.audits["cumulative-layout-shift"].numericValue;
      runs.push(scores);
    }
    results[id] = runs;
    for (const [metric, minimum] of Object.entries(thresholds)) {
      const values = runs.map((run) => run[metric]).sort((a, b) => a - b);
      const median = values[1];
      const floor = minimum - 0.05;
      if (median < minimum || values.some((value) => value < floor)) {
        failed = true;
        console.error(`${id}: ${metric} ${values.join(", ")} (median >= ${minimum}, each >= ${floor})`);
      }
    }
    const cls = runs.map((run) => run.cls);
    if (Math.max(...cls) > 0.1) {
      failed = true;
      console.error(`${id}: CLS ${cls.join(", ")} (each <= 0.1)`);
    }
  }
} finally {
  await chrome.kill();
  await new Promise((resolve) => server.close(resolve));
}

fs.writeFileSync(
  path.join(output, "summary.json"),
  JSON.stringify({ schema_version: "1.0.0", runs_per_route: 3, results }, null, 2),
);
if (failed) process.exitCode = 1;
