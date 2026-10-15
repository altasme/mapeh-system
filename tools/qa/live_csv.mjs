// Live check of Download CSV on the deployed site: signs in as admin, downloads, and compares the row count with
// what the database reports to the same admin over the API. Read-only.  LIVE_URL=https://<project>.pages.dev node tools/qa/live_csv.mjs
import { createRequire } from 'module'; import fs from 'fs'; import path from 'path';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_PATH || '/opt/node22/lib/node_modules/playwright');
const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const LIVE = process.env.LIVE_URL; if (!LIVE) { console.error('Set LIVE_URL'); process.exit(1); }
const legacy = fs.readFileSync(path.join(ROOT, 'legacy/mapehDavNor.original.html'), 'utf8');
const pw = Object.fromEntries([...legacy.matchAll(/username:\s*"([^"]+)",\s*password:\s*"([^"]+)"/g)].map(m => [m[1], m[2]]));
const cfg = await (await fetch(LIVE + '/config.js')).text();
const SB = cfg.match(/supabaseUrl:\s*"([^"]+)"/)[1], PUB = cfg.match(/supabasePublishableKey:\s*"([^"]+)"/)[1];
const tok = (await (await fetch(`${SB}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: PUB, 'Content-Type': 'application/json' }, body: JSON.stringify({ email: 'admin@users.mapehdavnor.altasme.app', password: pw.admin }) })).json()).access_token;
const dbCount = Number((await fetch(`${SB}/rest/v1/assessment_records?select=id&limit=1`, { headers: { apikey: PUB, Authorization: `Bearer ${tok}`, Prefer: 'count=exact' } })).headers.get('content-range').split('/')[1]);
let pass = 0, fail = 0; const ok = (c, m) => { c ? pass++ : fail++; console.log(`  ${c ? 'PASS' : 'FAIL'} ${m}`); };
const browser = await chromium.launch({ proxy: process.env.HTTPS_PROXY ? { server: process.env.HTTPS_PROXY } : undefined });
for (const user of ['admin', 'supervisor', 'carmen_coord']) {
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true, acceptDownloads: true }); const page = await ctx.newPage();
  await page.goto(LIVE); await page.fill('#login-username', user); await page.fill('#login-password', pw[user]); await page.click('#login-screen button[type=submit]');
  await page.waitForFunction(() => document.getElementById('login-screen').style.display === 'none', null, { timeout: 30000 });
  await page.waitForFunction(() => !document.querySelector('.view-loading') && document.getElementById('view-container').innerText.length > 20);
  if (user === 'carmen_elemcoord') { ok(!(await page.locator('#csv-btn').isVisible()), 'coordinator: no Download CSV button on the deployed site'); await ctx.close(); continue; }
  const [dl] = await Promise.all([page.waitForEvent('download', { timeout: 60000 }), page.click('#csv-btn')]);
  const f = `/tmp/claude-0/live-${user}.csv`; await dl.saveAs(f); const lines = fs.readFileSync(f, 'utf8').trim().split(/\r?\n/);
  ok(dl.suggestedFilename().startsWith('mapeh-assessment-records-'), `${user}: downloaded ${dl.suggestedFilename()}`);
  ok(lines[0].replace(/^﻿/, '').startsWith('School Year,Term,District,School Name'), `${user}: header row is in the import template's order`);
  ok(dbCount === 0 || lines.length - 1 >= dbCount, `${user}: ${lines.length - 1} data lines for ${dbCount} record(s) in the database`);
  await ctx.close();
}
console.log(`\n${pass} passed, ${fail} failed`); await browser.close(); process.exit(fail ? 1 : 0);
