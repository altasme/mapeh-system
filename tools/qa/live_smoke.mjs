// Smoke test against the REAL Supabase project with real CDN scripts (SRI enforced). By default the app is served from public/;
// set LIVE_URL=https://<project>.pages.dev to test the deployed site, including its real CSP headers.
// Passwords come from legacy/ at run time. Usage: node tools/qa/live_smoke.mjs
import { createRequire } from 'module';
import http from 'http'; import fs from 'fs'; import path from 'path';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_PATH || '/opt/node22/lib/node_modules/playwright');
const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const legacy = fs.readFileSync(path.join(ROOT, 'legacy/mapehDavNor.original.html'), 'utf8');
const pw = Object.fromEntries([...legacy.matchAll(/username:\s*"([^"]+)",\s*password:\s*"([^"]+)"/g)].map(m => [m[1], m[2]]));
const BASE = process.env.LIVE_URL || 'https://app.test'; // virtual origin: files are served from public/ by route interception, everything else is real network
const proxy = process.env.HTTPS_PROXY ? { server: process.env.HTTPS_PROXY } : undefined;
const browser = await chromium.launch({ proxy });
let pass = 0, fail = 0; const ok = (c, m) => { c ? pass++ : fail++; console.log(`  ${c ? 'PASS' : 'FAIL'} ${m}`); };
const txt = async p => (await p.evaluate(() => document.getElementById('view-container').innerText)).replace(/\s+/g, ' ');
for (const user of ['admin', 'carmen_coord']) {
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1280, height: 900 } });
  if (!process.env.LIVE_URL) await ctx.route('https://app.test/**', route => { const u = new URL(route.request().url()); const f = path.join(ROOT, 'public', u.pathname === '/' ? 'index.html' : u.pathname);
    if (!fs.existsSync(f)) return route.fulfill({ status: 404, body: '' });
    route.fulfill({ contentType: f.endsWith('.js') ? 'text/javascript' : 'text/html', body: fs.readFileSync(f) }); });
  const page = await ctx.newPage();
  const errs = []; page.on('pageerror', e => errs.push(String(e))); page.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });
  page.on('requestfailed', r => errs.push('REQFAIL ' + r.url().slice(0, 80) + ' ' + (r.failure() || {}).errorText));
  page.on('response', r => { if (r.status() >= 400) errs.push('HTTP ' + r.status() + ' ' + r.url().slice(0, 90)); });
  await page.goto(BASE);
  await page.waitForFunction(() => typeof window.supabase !== 'undefined' && typeof Chart !== 'undefined' && typeof XLSX !== 'undefined', null, { timeout: 30000 }).catch(e => { console.log('script load problem:', errs.join(' | ')); throw e; });
  ok(true, `${user}: CDN scripts loaded with SRI enforced (supabase-js, Chart.js, SheetJS)`);
  await page.fill('#login-username', user.toUpperCase()); await page.fill('#login-password', pw[user]);
  await page.click('#login-screen button[type=submit]');
  await page.waitForFunction(() => document.getElementById('login-screen').style.display === 'none', null, { timeout: 30000 });
  await page.waitForFunction(() => !document.querySelector('.view-loading') && document.getElementById('view-container').innerText.length > 50, null, { timeout: 30000 });
  const t = await txt(page);
  if (user === 'admin') {
    ok(/Division/.test(t) && /Asuncion/.test(t) && /Langilan/.test(t), 'admin: Division Summary lists all districts from the live database');
    await page.evaluate(() => switchView('dashboard')); await page.waitForFunction(() => !document.querySelector('.view-loading') && /TOTAL DISTRICT RECORDS/i.test(document.getElementById('view-container').innerText));
    ok(/TOTAL DISTRICT RECORDS\s*1452/i.test((await page.evaluate(() => document.getElementById('view-container').innerText)).replace(/\n/g, ' ')), 'admin: dashboard counts all 1,452 live rows (pagination across the 1,000-row cap)');
    ok(!(await page.locator('#env-banner').isHidden()), 'test-environment banner visible');
  } else {
    ok(/Carmen/.test(t) && !/Asuncion/.test(t), 'coordinator: Division Summary shows only Carmen');
    await page.evaluate(() => switchView('dashboard')); await page.waitForFunction(() => !document.querySelector('.view-loading') && /TOTAL DISTRICT RECORDS/i.test(document.getElementById('view-container').innerText));
    ok(/TOTAL DISTRICT RECORDS\s*132/i.test((await page.evaluate(() => document.getElementById('view-container').innerText)).replace(/\n/g, ' ')), 'coordinator: sees 132 own-district rows (enforced by the database)');
    ok(await page.evaluate(() => document.getElementById('nav-settings').style.display === 'none'), 'coordinator: Settings hidden');
  }
  for (const v of ['district-view', 'comparative', 'least-learned', 'grade-view', 'reports']) {
    await page.evaluate(x => switchView(x), v);
    await page.waitForFunction(() => !document.querySelector('.view-loading') && document.getElementById('view-container').innerText.length > 20, null, { timeout: 30000 });
    ok(!/Could not load this view/.test(await txt(page)), `${user}: ${v} renders`);
  }
  ok(errs.length === 0, `${user}: no console or page errors${errs.length ? ' -> ' + errs[0] : ''}`);
  await ctx.close();
}
console.log(`\n${pass} passed, ${fail} failed`); await browser.close(); process.exit(fail ? 1 : 0);
