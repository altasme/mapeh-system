// Screenshots of the app against the real project: node tools/qa/shots.mjs <outdir> [LIVE_URL or local]
// Local mode serves public/ through route interception (https://app.test). Passwords are read from legacy/ at run time.
import { createRequire } from 'module'; import fs from 'fs'; import path from 'path';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_PATH || '/opt/node22/lib/node_modules/playwright');
const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const OUT = process.argv[2] || '/tmp/claude-0/shots'; fs.mkdirSync(OUT, { recursive: true });
const LIVE = process.env.LIVE_URL; const BASE = LIVE || 'https://app.test';
const legacy = fs.readFileSync(path.join(ROOT, 'legacy/mapehDavNor.original.html'), 'utf8');
const pw = Object.fromEntries([...legacy.matchAll(/username:\s*"([^"]+)",\s*password:\s*"([^"]+)"/g)].map(m => [m[1], m[2]]));
const browser = await chromium.launch({ proxy: process.env.HTTPS_PROXY ? { server: process.env.HTTPS_PROXY } : undefined });
const VIEWS = ['division', 'district-view', 'comparative', 'dashboard', 'data-input', 'least-learned', 'grade-view', 'settings'];
const user = process.env.SHOT_USER || 'admin';
for (const [tag, vp] of [['d', { width: 1440, height: 900 }], ['m', { width: 390, height: 844 }]]) {
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true, viewport: vp, deviceScaleFactor: 1 });
  if (!LIVE) await ctx.route('https://app.test/**', r => { const u = new URL(r.request().url()); const f = path.join(ROOT, 'public', u.pathname === '/' ? 'index.html' : u.pathname);
    fs.existsSync(f) ? r.fulfill({ contentType: f.endsWith('.js') ? 'text/javascript' : 'text/html', body: fs.readFileSync(f) }) : r.fulfill({ status: 404, body: '' }); });
  const page = await ctx.newPage();
  await page.goto(BASE); await page.waitForSelector('#login-username');
  await page.screenshot({ path: `${OUT}/${tag}-login.png` });
  await page.fill('#login-username', user); await page.fill('#login-password', pw[user]); await page.click('#login-screen button[type=submit]');
  await page.waitForFunction(() => document.getElementById('login-screen').style.display === 'none', null, { timeout: 30000 });
  for (const v of VIEWS) {
    await page.evaluate(x => { formDirty = false; switchView(x); }, v);
    await page.waitForFunction(() => !document.querySelector('#view-container .view-loading') && document.getElementById('view-container').innerText.length > 20, null, { timeout: 30000 });
    await page.waitForTimeout(700);
    await page.screenshot({ path: `${OUT}/${tag}-${v}.png`, fullPage: tag === 'm' ? false : false });
  }
  await ctx.close();
}
await browser.close(); console.log('shots in', OUT);
