/**
 * Captures iBuild store screenshots from the web build in demo mode.
 *
 *   flutter build web --release
 *   node tool/screenshots/capture.mjs <out-dir>     (needs playwright + Chrome)
 *
 * Flutter web draws to a canvas, so the script turns on Flutter's semantics
 * tree and taps widgets by their accessible names, the way a screen reader
 * would. Demo builds take about 40 seconds, so the waits are real.
 */
import { chromium } from "playwright";
import { createServer } from "http";
import { readFile, mkdir } from "fs/promises";
import { join, extname, dirname } from "path";
import { fileURLToPath } from "url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "build", "web");
const OUT = process.argv[2];
const types = { ".js": "text/javascript", ".html": "text/html", ".wasm": "application/wasm", ".json": "application/json", ".png": "image/png", ".otf": "font/otf", ".ttf": "font/ttf", ".css": "text/css" };
const PORT = 8143;
const server = createServer(async (req, res) => {
  let p = decodeURIComponent(req.url.split("?")[0]);
  if (p.endsWith("/")) p += "index.html";
  try {
    const body = await readFile(join(ROOT, p));
    res.writeHead(200, { "content-type": types[extname(p)] || "application/octet-stream" });
    res.end(body);
  } catch {
    res.writeHead(200, { "content-type": "text/html" });
    res.end(await readFile(join(ROOT, "index.html")));
  }
}).listen(PORT);

const PROFILES = {
  phone: { width: 430, height: 932, dpr: 3 },    // 1290x2796
  // iPad-mini-sized viewport: the app column fills the frame instead of
  // sitting small in the middle of a 13" canvas.
  tablet: { width: 768, height: 1024, dpr: 2.6875 }, // 2064x2752
};

const browser = await chromium.launch({ channel: "chrome" });
for (const [name, v] of Object.entries(PROFILES)) {
  const out = join(OUT, name);
  await mkdir(out, { recursive: true });
  const page = await browser.newPage({ viewport: { width: v.width, height: v.height }, deviceScaleFactor: v.dpr });
  const tap = async (re, nth = 0) => {
    const el = page.getByRole("button", { name: re }).or(page.getByRole("tab", { name: re })).nth(nth);
    await el.click({ timeout: 15000 });
    await page.waitForTimeout(1200);
  };
  const shot = async (file) => {
    await page.mouse.move(2, 2);
    await page.waitForTimeout(600);
    await page.screenshot({ path: join(out, file) });
    console.log(`  ${name}/${file}`);
  };

  await page.goto(`http://localhost:${PORT}/`, { waitUntil: "networkidle" });
  await page.waitForTimeout(5000);
  await page.evaluate(() => document.querySelector("flt-semantics-placeholder")?.click());
  await page.waitForTimeout(1500);

  // 1. A build travelling the line.
  await tap(/^Build & test$/);
  await page.waitForTimeout(17000);
  await shot("01_dashboard.png");

  // 2. Its live log: open the build and expand the step that is compiling.
  await tap(/^Watch Build #\d+$/);
  await page.waitForTimeout(6000);
  await tap(/Flutter build ipa/);
  await page.waitForTimeout(4000);
  await shot("02_build.png");
  await page.goBack().catch(() => {});
  await page.keyboard.press("Escape").catch(() => {});
  await page.waitForTimeout(25000); // let it finish and reach TestFlight

  // 3. History.
  await tap(/^History/);
  await shot("03_history.png");

  // 4. TestFlight testers.
  await tap(/^TestFlight$/);
  await page.waitForTimeout(1500);
  await shot("04_testflight.png");

  // 5. The same project's Android workflow, ending at a Play draft.
  await tap(/^Build$/);
  await tap(/^Workflow/);
  await tap(/^android-release$/);
  await tap(/^Build & test$/);
  await page.waitForTimeout(45000);
  await shot("05_android.png");
  await page.close();
}
await browser.close();
server.close();
