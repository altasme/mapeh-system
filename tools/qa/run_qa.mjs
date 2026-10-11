// QA harness: runs the ORIGINAL app and the PORTED app side by side in Chromium and compares what they show.
// The ported app talks to tools/qa/stub-supabase.js (in-memory). Real RLS is tested by supabase/tests/rls_matrix.sql.
// Usage: node tools/qa/run_qa.mjs   (needs playwright, chart.js / xlsx / supabase files cached in $CDN_DIR)
import { createRequire } from 'module';
import http from 'http';
import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_PATH || '/opt/node22/lib/node_modules/playwright');

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const CDN = process.env.CDN_DIR || '/tmp/claude-0/cdn';
const OUT = process.env.QA_OUT || '/tmp/claude-0/qa-out';
fs.mkdirSync(OUT, { recursive: true });
const stubJs = fs.readFileSync(path.join(ROOT, 'tools/qa/stub-supabase.js'), 'utf8');
const demo = JSON.parse(execSync(`python3 ${ROOT}/tools/gen_demo_records.py --json`, { maxBuffer: 1 << 26 }).toString());
const fixture = JSON.parse(fs.readFileSync(path.join(ROOT, 'fixtures/regression.json'), 'utf8'));

let pass = 0, fail = 0;
const ok = (c, msg) => { if (c) { pass++; console.log('  PASS', msg); } else { fail++; console.log('  FAIL', msg); } };

// ---------- static server ----------
const server = http.createServer((req, res) => {
  const p = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]));
  if (!p.startsWith(ROOT) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); return res.end(); }
  const type = p.endsWith('.html') ? 'text/html' : p.endsWith('.js') ? 'text/javascript' : 'text/plain';
  res.writeHead(200, { 'content-type': type });
  res.end(fs.readFileSync(p));
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const BASE = `http://127.0.0.1:${server.address().port}`;

// ---------- data for the stand-in ----------
const seedSql = fs.readFileSync(path.join(ROOT, 'supabase/seed/districts.sql'), 'utf8');
const seedRows = [...seedSql.matchAll(/\('([^']+)',\s*'([^']+)',\s*'([^']+)',\s*(\d+)\)/g)];
const districts = seedRows.map(m => ({ id: Number(m[4]), name: m[1], coordinator_name: m[2], coordinator_position: m[3], sort_order: Number(m[4]) }));
const ACCOUNTS = [
  ['admin', 'System Administrator', 'admin', null], ['supervisor', 'Education Program Supervisor', 'supervisor', null],
  ['asuncion_coord', 'Asuncion District Coordinator', 'district_coordinator', 'Asuncion'],
  ['dujali_coord', 'B.E. Dujali District Coordinator', 'district_coordinator', 'B.E. Dujali'],
  ['carmen_coord', 'Carmen District Coordinator', 'district_coordinator', 'Carmen'],
  ['kapalonge_coord', 'Kapalong East District Coordinator', 'district_coordinator', 'Kapalong East'],
  ['kapalongw_coord', 'Kapalong West District Coordinator', 'district_coordinator', 'Kapalong West'],
  ['newcorella_coord', 'New Corella District Coordinator', 'district_coordinator', 'New Corella'],
  ['sanisidro_coord', 'San Isidro District Coordinator', 'district_coordinator', 'San Isidro'],
  ['stotomase_coord', 'Sto. Tomas East District Coordinator', 'district_coordinator', 'Sto. Tomas East'],
  ['stotomasw_coord', 'Sto. Tomas West District Coordinator', 'district_coordinator', 'Sto. Tomas West'],
  ['talaingod_coord', 'Talaingod District Coordinator', 'district_coordinator', 'Talaingod'],
  ['langilan_coord', 'Langilan District Coordinator', 'district_coordinator', 'Langilan'],
];
const profiles = ACCOUNTS.map(([username, display_name, role, dn], i) => ({
  id: `00000000-0000-0000-0000-${String(i + 1).padStart(12, '0')}`, username, display_name, role,
  district_id: dn ? districts.find(d => d.name === dn).id : null }));
const settingsSeed = (() => { // parse supabase/seed/settings.sql json
  const s = fs.readFileSync(path.join(ROOT, 'supabase/seed/settings.sql'), 'utf8');
  return JSON.parse(s.slice(s.indexOf("'{") + 1, s.lastIndexOf("}'") + 1));
})();
const toRowish = r => ({ sy: r.sy, term: r.term, district_id: districts.find(d => d.name === r.district).id, school: r.school,
  key_stage: r.keyStage, grade_level: r.gradeLevel, learning_area: r.learningArea, baseline_mps: r.baselineMps, mps: r.mps,
  pct75: r.pct75, proficiency_level: r.proficiencyLevel, least_learned: r.leastLearned, is_demo: r.isDemo !== false });

// ---------- browser plumbing ----------
const browser = await chromium.launch();
let legacyInfo = null; // passwords etc. read from the legacy file, kept in memory only
async function context(kind, viewport) {
  const ctx = await browser.newContext({ viewport: viewport || { width: 1280, height: 900 }, acceptDownloads: true });
  await ctx.route('**/*', async route => {
    const u = route.request().url();
    if (u.startsWith(BASE)) {
      if (u.endsWith('/public/config.js')) return route.fulfill({ contentType: 'text/javascript', body:
        'window.APP_CONFIG={environment:"test",supabaseUrl:"https://qa.invalid",supabasePublishableKey:"qa-key",authEmailDomain:"users.mapehdavnor.altasme.app",features:{}};' });
      if (u.endsWith('/public/index.html')) {   // QA only: drop SRI because the stand-in replaces the real supabase file
        const html = fs.readFileSync(path.join(ROOT, 'public/index.html'), 'utf8').replace(/ integrity="[^"]+"/g, '');
        return route.fulfill({ contentType: 'text/html', body: html });
      }
      return route.continue();
    }
    if (/chart\.js@4\.4\.1/.test(u)) return route.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(`${CDN}/chart.js`) });
    if (/xlsx@0\.18\.5/.test(u)) return route.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(`${CDN}/xlsx0185.js`) });
    if (/sheetjs\.com/.test(u)) return route.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(`${CDN}/xlsx.js`) });
    if (/supabase-js/.test(u)) return route.fulfill({ contentType: 'text/javascript', body: stubJs });
    return route.abort();
  });
  return ctx;
}
async function readPasswords() {
  if (legacyInfo) return legacyInfo;
  const ctx = await context('legacy'); const page = await ctx.newPage();
  await page.goto(`${BASE}/legacy/mapehDavNor.original.html`);
  const passwords = await page.evaluate(() => Object.fromEntries(USER_ACCOUNTS.map(a => [a.username, a.password])));
  const legacyCoords = await page.evaluate(() => districtCoordinators);
  const legacySettings = await page.evaluate(() => settings);
  const legacyDistricts = await page.evaluate(() => DEFAULT_DISTRICTS);
  await ctx.close();
  legacyInfo = { passwords, legacyCoords, legacySettings, legacyDistricts };
  return legacyInfo;
}
const norm = s => s.replace(/[ \t ]+/g, ' ').replace(/\n\s*\n+/g, '\n').trim();

async function openLegacy(username, records, viewport) {
  const ctx = await context('legacy', viewport); const page = await ctx.newPage();
  const acct = ACCOUNTS.find(a => a[0] === username);
  const roleLabel = { admin: 'Admin', supervisor: 'Supervisor', district_coordinator: 'District Coordinator' }[acct[2]];
  await page.addInitScript(([u]) => { sessionStorage.setItem('deped_current_user', JSON.stringify(u)); localStorage.setItem('deped_db_has_been_seeded', 'true'); },
    [{ name: acct[1], role: roleLabel, username, district: acct[3] || 'ALL' }]);
  await page.goto(`${BASE}/legacy/mapehDavNor.original.html`);
  await page.waitForFunction(() => typeof db !== 'undefined' && !!db);
  await page.evaluate(async r => { await clearDatabase(); await bulkInsert(r); }, records);
  await page.evaluate(() => switchView('division'));
  return { ctx, page };
}
async function openNew(username, records, extra = {}, viewport) {
  const { passwords: pw } = await readPasswords();
  const ctx = await context('new', viewport); const page = await ctx.newPage();
  const errors = []; page.on('pageerror', e => errors.push(String(e)));
  const stub = { districts: JSON.parse(JSON.stringify(districts)), profiles, passwords: pw, records: records.map((r, i) => Object.assign({ id: i + 1 }, toRowish(r))),
    notes: extra.notes || [], settings: JSON.parse(JSON.stringify(settingsSeed)) };
  await page.addInitScript(s => { window.__STUB = s; }, stub);
  await page.goto(`${BASE}/public/index.html`);
  if (!extra.noLogin) {
    await page.fill('#login-username', username); await page.fill('#login-password', pw[username]);
    await page.click('#login-screen button[type=submit]');
    await page.waitForFunction(() => document.getElementById('login-screen').style.display === 'none');
    await settled(page);
  }
  return { ctx, page, errors };
}
async function settled(page) {
  await page.waitForFunction(() => !document.querySelector('#view-container .view-loading') && document.getElementById('view-container').innerText.length > 0, null, { timeout: 15000 });
}
async function legacyReady(page) {
  await page.waitForFunction(() => document.getElementById('view-container').children.length > 0, null, { timeout: 15000 });
  await page.waitForTimeout(150);
}
// Screen-only additions (sheet letterhead, proficiency rulers) are presentation: hide them before reading text.
const text = async page => norm(await page.evaluate(() => {
  if (!document.getElementById('qa-hide')) { const st = document.createElement('style'); st.id = 'qa-hide'; st.textContent = '.screen-only{display:none!important}'; document.head.appendChild(st); }
  return document.getElementById('view-container').innerText;
}));
const charts = async page => page.evaluate(() => Object.values(activeCharts).map(c => c.data.datasets[0].data.map(Number)));

async function goView(L, N, view, filt) {
  for (const [p, isNew] of [[L.page, false], [N.page, true]]) {
    const wait = async () => { if (isNew) await settled(p); else { await legacyReady(p); await p.waitForTimeout(350); } };
    await p.evaluate(v => switchView(v), view); await wait();
    if (filt) {
      await p.evaluate(f => { for (const [id, val] of Object.entries(f)) document.getElementById(id).value = val; applyFilters(); }, filt);
      await wait();
    }
  }
}
// The ONLY intended rendering differences are the empty states (spec 9.6). Map the original's empty renderings
// and the ported "No data" onto one token so everything else must match exactly.
function canonLegacy(t) {
  return t.toLowerCase().replace(/\s+/g, ' ').trim()
    .replace(/(?<![\d.])0\.00% (?<![\d.])0\.00% \+?0\.00% maintained beginning/g, '- - - - -')
    .replace(/-65\.00% decreased beginning/g, '- - -')
    .replace(/(?<![\d.])(?:0\.00%|0%) beginning/g, 'nd');
}
function canonPorted(t) { return t.toLowerCase().replace(/\s+/g, ' ').trim().replace(/no data no data/g, 'nd').replace(/no data/g, 'nd'); }
function firstDiff(a, b) {
  const A = a.split(' '), B = b.split(' ');
  for (let i = 0; i < Math.max(A.length, B.length); i++) if (A[i] !== B[i]) return `    legacy: ...${A.slice(Math.max(0, i - 6), i + 8).join(' ')}\n    ported: ...${B.slice(Math.max(0, i - 6), i + 8).join(' ')}`;
  return '';
}
function diffLines(a, b) {
  const A = a.split('\n'), B = b.split('\n'); const out = [];
  const n = Math.max(A.length, B.length);
  for (let i = 0; i < n; i++) if (A[i] !== B[i]) out.push(`    legacy: ${A[i] ?? '(none)'}\n    ported: ${B[i] ?? '(none)'}`);
  return out;
}

const VIEWS = ['division', 'district-view', 'comparative', 'dashboard', 'least-learned', 'grade-view', 'reports'];
const FILTERS = [null, { 'flt-term': 'Term 1' }, { 'flt-term': 'ALL', 'flt-keystage': 'Key Stage 3' }, { 'flt-keystage': 'ALL', 'flt-subject': 'SPS - Basketball' }, { 'flt-subject': 'ALL', 'flt-district': 'Carmen' }];

// =================================================================
console.log('\n[1] Seed fidelity: districts, coordinators, settings and constants match the original');
{
  const { legacyCoords, legacySettings, legacyDistricts } = await readPasswords();
  ok(JSON.stringify(districts.map(d => d.name)) === JSON.stringify(legacyDistricts), 'district list and order identical');
  ok(districts.every(d => legacyCoords[d.name].name === d.coordinator_name && legacyCoords[d.name].position === d.coordinator_position), 'coordinator defaults identical (seed vs original)');
  ok(JSON.stringify(settingsSeed) === JSON.stringify(legacySettings), 'settings defaults identical (seed vs original)');
  ok(profiles.length === 13, '13 accounts provisioned per Appendix D');
}

console.log('\n[2] Parity on the 1,452-row sample set (admin): every view, 5 filter combinations');
{
  const L = await openLegacy('admin', demo); const N = await openNew('admin', demo);
  await legacyReady(L.page);
  for (const f of FILTERS) {
    for (const v of VIEWS) {
      await goView(L, N, v, f);
      const a = canonLegacy(await text(L.page)), b = canonPorted(await text(N.page));
      const label = `${v} / ${f ? JSON.stringify(f) : 'no filter'}`;
      ok(a === b, label);
      if (a !== b) console.log(firstDiff(a, b));
      if (v === 'dashboard') ok(JSON.stringify(await charts(L.page)) === JSON.stringify(await charts(N.page)), `dashboard chart data / ${f ? JSON.stringify(f) : 'no filter'}`);
    }
  }
  ok(N.errors.length === 0, 'no uncaught page errors in the ported app' + (N.errors.length ? ': ' + N.errors[0] : ''));
  // pagination: 1452 rows > 1000-row cap
  await N.page.evaluate(() => { resetFilters(); switchView('dashboard'); }); await settled(N.page);
  const t = await text(N.page);
  ok(/TOTAL DISTRICT RECORDS\s+1452/i.test(t), 'pagination: all 1,452 rows are read although the server caps responses at 1,000');
  await L.ctx.close(); await N.ctx.close();
}

console.log('\n[3] Regression fixture: hand-computed expectations (fixtures/regression.json)');
{
  const recs = fixture.records.map(r => Object.assign({ proficiencyLevel: '', isDemo: false, leastLearned: [] }, r));
  const E = fixture.expected;
  const N = await openNew('admin', recs); const L = await openLegacy('admin', recs); await legacyReady(L.page);
  await N.page.evaluate(() => switchView('division')); await settled(N.page);
  let t = await text(N.page);
  ok(t.includes(E.divisionSummary.divisionMps.toFixed(2) + '%'), `Division Summary shows division MPS ${E.divisionSummary.divisionMps.toFixed(2)}% (mean of district term means)`);
  ok(/Asuncion[\s\S]*85\.00%[\s\S]*85\.00%/.test(t) && /Carmen[\s\S]*70\.00%[\s\S]*95\.00%[\s\S]*82\.50%/.test(t), 'district term means and consolidated MPS as computed by hand');
  await N.page.evaluate(() => switchView('dashboard')); await settled(N.page); t = await text(N.page);
  ok(new RegExp('(^|[^\\d.])' + E.dashboard.flatMps + '(\\.00)?%').test(t), `Dashboard shows flat MPS ${E.dashboard.flatMps.toFixed(2)}% (AUDIT M3: differs from Division Summary)`);
  ok(new RegExp('(^|[^\\d.])' + E.dashboard.pct75 + '(\\.00)?%').test(t), `Dashboard shows % learners >= 75 at ${E.dashboard.pct75.toFixed(2)}%`);
  await N.page.evaluate(() => switchView('comparative')); await settled(N.page); t = await text(N.page);
  const baselines = await N.page.evaluate(() => Array.from(document.querySelectorAll('.editable-baseline-input')).map(i => i.value));
  Object.entries(E.comparativeByKeyStage).forEach(([ks, v], idx) => {
    const row = t.split('\n').find(l => l.startsWith(ks)) || '';
    ok(Number(baselines[idx]) === v.baseline && row.includes(v.mps.toFixed(2) + '%') && row.includes((v.variance > 0 ? '+' : '') + v.variance.toFixed(2) + '%'), `Comparative ${ks}: baseline ${v.baseline}, MPS ${v.mps}, variance ${v.variance}`);
  });
  const plChecks = await N.page.evaluate(c => Object.fromEntries(Object.keys(c).map(k => [k, getPL(Number(k))])), E.proficiencyCutoffs);
  ok(JSON.stringify(plChecks) === JSON.stringify(E.proficiencyCutoffs), 'getPL cutoffs 90/85/80/75 unchanged');
  // Same fixture in both apps: only empty-state rendering may differ
  for (const v of VIEWS) {
    await goView(L, N, v, null);
    const a = canonLegacy(await text(L.page)), b = canonPorted(await text(N.page));
    ok(a === b, `fixture parity: ${v}`);
    if (a !== b) console.log(firstDiff(a, b));
  }
  await L.ctx.close(); await N.ctx.close();
}

console.log('\n[4] Security: stored XSS is neutralised (and was live in the original)');
{
  const evil = Object.assign({}, demo[0], { school: '<img src=x onerror="window.__pwned=1">', learningArea: 'SPA - Vocal Arts',
    leastLearned: [{ code: '<b>X</b>', desc: '</td><img src=x onerror="window.__pwned=1">' }] });
  const L = await openLegacy('admin', [evil]); await legacyReady(L.page);
  for (const v of ['district-view', 'least-learned']) { await L.page.evaluate(x => switchView(x), v); await L.page.waitForTimeout(400); }
  ok(await L.page.evaluate(() => window.__pwned === 1), 'original app: payload executes (confirms audit C4)');
  const N = await openNew('admin', [evil]);
  for (const v of ['district-view', 'least-learned', 'division']) { await N.page.evaluate(x => switchView(x), v); await settled(N.page); await N.page.waitForTimeout(300); }
  ok(await N.page.evaluate(() => window.__pwned === undefined), 'ported app: payload is rendered as text and never executes');
  await N.page.evaluate(() => switchView('least-learned')); await settled(N.page);
  ok((await text(N.page)).includes('<img src=x'), 'ported app: payload is visible as literal text');
  // notes with </textarea>
  await N.page.evaluate(() => switchView('comparative')); await settled(N.page);
  await N.page.fill('#comp-analysis-input', '</textarea><img src=x onerror="window.__pwned=2">');
  await N.page.click('text=Save Qualitative Notes'); await N.page.waitForSelector('.toast-success');
  await N.page.evaluate(() => { formDirty = false; switchView('comparative'); }); await settled(N.page);
  ok(await N.page.evaluate(() => window.__pwned === undefined && document.getElementById('comp-analysis-input').value.startsWith('</textarea>')), 'notes containing </textarea> round-trip safely');
  await L.ctx.close(); await N.ctx.close();
}

console.log('\n[5] Roles: coordinator scope, settings access, destructive actions');
{
  const N = await openNew('carmen_coord', demo);
  await N.page.evaluate(() => switchView('division')); await settled(N.page);
  let t = await text(N.page);
  ok(t.includes('Carmen') && !t.includes('Asuncion'), 'coordinator sees only own district (Division Summary)');
  ok(await N.page.evaluate(() => document.getElementById('nav-settings').style.display === 'none'), 'Settings & Branding hidden for coordinator');
  await N.page.evaluate(() => switchView('dashboard')); await settled(N.page);
  ok(/TOTAL DISTRICT RECORDS\s+132/i.test(await text(N.page)), 'coordinator sees 132 own-district records only (database filtered)');
  await N.page.evaluate(() => switchView('settings')); await settled(N.page);
  ok((await text(N.page)).includes('Access Restricted'), 'Settings view refuses a coordinator');
  await N.ctx.close();

  const A = await openNew('admin', demo);
  await A.page.evaluate(() => switchView('settings')); await settled(A.page);
  A.page.on('dialog', d => d.accept());
  await A.page.selectOption('#clear-sy-select', '2025-2026');
  await A.page.click('text=Delete Selected SY Records');
  await A.page.waitForSelector('#reauth-modal', { state: 'visible' });
  await A.page.fill('#reauth-password', 'wrong-password'); await A.page.click('#reauth-ok');
  await A.page.waitForFunction(() => document.getElementById('reauth-error').textContent.length > 0);
  ok((await A.page.textContent('#reauth-error')).includes('Incorrect'), 're-auth modal rejects a wrong password');
  ok(await A.page.evaluate(() => document.getElementById('reauth-password').type === 'password'), 'password field is masked (type=password)');
  ok(await A.page.evaluate(() => window.__STUB.records.length === 1452), 'nothing deleted after a wrong password');
  await A.page.fill('#reauth-password', (await readPasswords()).passwords.admin); await A.page.click('#reauth-ok');
  await A.page.waitForSelector('.toast-success');
  ok(/1452 assessment record/.test(await A.page.textContent('#toast-host')), 'correct password: delete succeeds and the confirmed count (1452) is reported');
  ok(await A.page.evaluate(() => window.__STUB.records.length === 0), 'records are gone');
  await A.ctx.close();
}

console.log('\n[6] Writes: confirmed saves, constraint errors, all-or-nothing import, unknown district');
{
  const N = await openNew('admin', demo.slice(0, 20));
  const xlsx = async rows => N.page.evaluate(r => { const ws = XLSX.utils.json_to_sheet(r); const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, ws, 'S'); return Array.from(new Uint8Array(XLSX.write(wb, { type: 'array', bookType: 'xlsx' }))); }, rows);
  const upload = async rows => { await N.page.evaluate(() => switchView('data-input')); await settled(N.page);
    await N.page.setInputFiles('#excel-file', { name: 't.xlsx', mimeType: 'application/octet-stream', buffer: Buffer.from(await xlsx(rows)) }); };
  const base = { 'School Year': '2025-2026', Term: 'Term 1', District: 'Asuncion', 'School Name': 'X', 'Key Stage': 'Key Stage 1', 'Grade Level': 'Grade 1', 'Learning Area': 'MAPEH - Music & Arts', 'SY Baseline MPS': 65, 'Mean Percentage Score (MPS%)': 80, '% Learners Scoring >= 75%': 70, 'Least Learned Competency 1 Description': 'lc one' };
  const count = () => N.page.evaluate(() => window.__STUB.records.length);
  await upload([base, Object.assign({}, base, { District: 'Atlantis' }), Object.assign({}, base, { District: 'Nowhere' })]);
  await N.page.waitForSelector('.toast-error');
  let tmsg = await N.page.textContent('#toast-host');
  ok(/Unknown district in 2 row/.test(tmsg) && /row 3: "Atlantis"/.test(tmsg) && /row 4: "Nowhere"/.test(tmsg), 'unknown district: rejected with row numbers and values');
  ok(await count() === 20, 'unknown district: nothing saved (whole file rejected)');
  await N.page.evaluate(() => document.getElementById('toast-host').innerHTML = '');
  await upload([base, Object.assign({}, base, { 'Mean Percentage Score (MPS%)': 150 })]);
  await N.page.waitForSelector('.toast-error'); tmsg = await N.page.textContent('#toast-host');
  ok(/Nothing was saved\. MPS must be between 0 and 100/.test(tmsg), 'MPS 150: plain-English database error, no partial save');
  ok(await count() === 20, 'MPS 150: nothing saved (one bad row rejects the file)');
  await N.page.evaluate(() => document.getElementById('toast-host').innerHTML = '');
  await upload([base, Object.assign({}, base, { Term: 'Term 2' })]);
  await N.page.waitForSelector('.toast-success');
  ok(/imported 2/.test(await N.page.textContent('#toast-host')) && await count() === 22, 'valid file: success toast only after the write, 2 rows saved');
  // manual entry, offline
  await N.page.evaluate(() => switchView('data-input')); await settled(N.page);
  await N.page.click('text=Method 2: Fast Manual Entry');
  await N.page.fill('#m-mps', '88'); await N.page.fill('#m-pct75', '77');
  await N.page.evaluate(() => { window.__STUB_OFFLINE = true; });
  await N.page.click('button:has-text("Save District Record")');
  await N.page.waitForSelector('.toast-error');
  ok(/Could not reach the server/.test(await N.page.textContent('#toast-host')) && await count() === 22, 'offline: readable error, no false success, nothing saved');
  await N.page.evaluate(() => { window.__STUB_OFFLINE = false; document.getElementById('toast-host').innerHTML = ''; });
  await N.page.click('button:has-text("Save District Record")');
  await N.page.waitForSelector('.toast-success');
  ok(await count() === 23, 'manual entry saved after reconnect');
  ok(await N.page.evaluate(() => !document.querySelector('#view-container button[disabled]')), 'submit button re-enabled after the request');
  // baseline edit shows a count and asks first
  await N.page.evaluate(() => switchView('comparative')); await settled(N.page);
  let asked = '';
  N.page.once('dialog', d => { asked = d.message(); d.dismiss(); });
  await N.page.fill('.editable-baseline-input >> nth=0', '70'); await N.page.keyboard.press('Tab');
  await N.page.waitForTimeout(400);
  ok(/This will change the baseline on \d+ record/.test(asked), 'baseline edit: asks "This will change the baseline on N records" first');
  ok(await N.page.evaluate(() => window.__STUB.records.every(r => r.baseline_mps !== 70)), 'baseline edit: dismissing the prompt changes nothing');
  await N.ctx.close();
}

console.log('\n[7] Unsaved-changes guard, keyboard access, login errors, sample-data flag');
{
  const N = await openNew('admin', demo.slice(0, 50));
  await N.page.evaluate(() => switchView('comparative')); await settled(N.page);
  await N.page.fill('#comp-analysis-input', 'draft');
  let msg = '';
  N.page.once('dialog', d => { msg = d.message(); d.dismiss(); });
  await N.page.click('.nav-item:has-text("Performance Dashboard")');
  await N.page.waitForTimeout(300);
  ok(/unsaved changes/i.test(msg) && (await N.page.evaluate(() => currentView)) === 'comparative', 'leaving with unsaved notes asks first; Cancel stays on the page');
  await N.page.evaluate(() => { formDirty = false; });
  await N.page.focus('.nav-item:has-text("Grade Level Breakdown")'); await N.page.keyboard.press('Enter');
  await settled(N.page);
  ok((await N.page.evaluate(() => currentView)) === 'grade-view', 'nav item works from the keyboard (Enter)');
  ok(await N.page.evaluate(() => document.querySelectorAll('.nav-item[role=button][tabindex="0"]').length === 9), 'all 9 nav items have role=button and tabindex=0');
  ok(await N.page.evaluate(() => !document.getElementById('env-banner').hidden), 'test-environment banner is visible');
  await N.page.emulateMedia({ media: 'print' });
  ok(await N.page.evaluate(() => getComputedStyle(document.getElementById('print-sample-line')).display === 'block' && getComputedStyle(document.getElementById('env-banner')).display === 'none'), 'print: "SAMPLE DATA" line shown when sample rows are in view; banner not printed');
  await N.page.emulateMedia({ media: 'screen' });
  await N.ctx.close();

  const none = await openNew('admin', []); // no sample rows in the filter
  await none.page.emulateMedia({ media: 'print' });
  ok(await none.page.evaluate(() => getComputedStyle(document.getElementById('print-sample-line')).display === 'none'), 'print: no SAMPLE DATA line when no sample rows are in view');
  await none.page.emulateMedia({ media: 'screen' });
  await none.page.evaluate(() => switchView('division')); await settled(none.page);
  ok(/No data/.test(await text(none.page)) && !/0\.00%/.test(await text(none.page)), 'empty state shows "No data" instead of 0.00% / Beginning');
  await none.ctx.close();

  const bad = await openNew('admin', [], { noLogin: true });
  const { passwords: pw } = await readPasswords();
  await bad.page.fill('#login-username', 'ADMIN'); await bad.page.fill('#login-password', 'nope');
  await bad.page.click('#login-screen button[type=submit]'); await bad.page.waitForTimeout(300);
  ok(/Invalid Username or Password/.test(await bad.page.textContent('#login-error')), 'wrong password: same message as before, inline');
  await bad.page.fill('#login-username', 'ADMIN'); await bad.page.fill('#login-password', pw.admin);
  await bad.page.click('#login-screen button[type=submit]');
  await bad.page.waitForFunction(() => document.getElementById('login-screen').style.display === 'none');
  ok(await bad.page.evaluate(() => currentUser.role === 'Admin' && currentUser.district === 'ALL'), 'username is case-insensitive; currentUser built from the profile');
  ok(await bad.page.evaluate(() => !sessionStorage.getItem('deped_current_user')), 'no trusted user object in sessionStorage');
  await Promise.all([bad.page.waitForEvent('load'), bad.page.click('button:has-text("Logout")')]);
  await bad.page.waitForFunction(() => document.getElementById('login-screen') && document.getElementById('login-screen').style.display !== 'none' && !document.getElementById('login-password').value);
  ok(await bad.page.evaluate(() => !sessionStorage.getItem('stub_session')), 'logout: session cleared and the login screen is back (page reloaded, filters reset)');
  await bad.ctx.close();
}

console.log('\n[8] Phone width (360 px): no page-level horizontal scroll, drawer navigation');
{
  const N = await openNew('admin', demo, {}, { width: 360, height: 740 });
  const widths = {};
  for (const v of ['division', 'district-view', 'comparative', 'dashboard', 'data-input', 'least-learned', 'grade-view', 'reports', 'settings']) {
    await N.page.evaluate(x => switchView(x), v); await settled(N.page); await N.page.waitForTimeout(250);
    widths[v] = await N.page.evaluate(() => document.documentElement.scrollWidth);
    await N.page.screenshot({ path: `${OUT}/m360-${v}.png`, fullPage: false });
  }
  for (const [v, w] of Object.entries(widths)) ok(w <= 360, `360px: ${v} (page width ${w})`);
  ok(await N.page.evaluate(() => getComputedStyle(document.getElementById('nav-toggle')).display !== 'none'), 'menu button visible on phones');
  ok(await N.page.evaluate(() => document.getElementById('sidebar').getBoundingClientRect().right <= 0), 'sidebar is off-canvas until opened');
  await N.page.click('#nav-toggle');
  await N.page.waitForTimeout(250);
  ok(await N.page.evaluate(() => document.getElementById('sidebar').getBoundingClientRect().left >= 0), 'drawer opens from the menu button');
  await N.ctx.close();
}

console.log('\n[9] Print CSS: the original @media print block is byte-identical');
{
  const grab = f => { const s = fs.readFileSync(path.join(ROOT, f), 'utf8').replace(/\r\n/g, '\n'); const i = s.indexOf('/* PRINT STYLES */'); return s.slice(i, s.indexOf('.print-only-header, .print-only-footer, .print-signatories { display: none; }', i)); };
  const legacyPrint = grab('legacy/mapehDavNor.original.html');
  const portedAll = fs.readFileSync(path.join(ROOT, 'public/index.html'), 'utf8').replace(/\r\n/g, '\n');
  ok(portedAll.includes(legacyPrint.trimEnd()), 'original print block present verbatim in the ported file');
}

console.log('\n[10] Print output: PDFs of the original and the ported app for division and district scope');
{
  for (const [user, label, view] of [['admin', 'division', 'comparative'], ['carmen_coord', 'district', 'comparative'], ['admin', 'division-dashboard', 'dashboard']]) {
    const L = await openLegacy(user, demo); const N = await openNew(user, demo);
    await legacyReady(L.page);
    await goView(L, N, view, null);
    // hide only the QA-irrelevant banner difference: the ported page has no extra on-screen element in print
    const files = [];
    // ported is printed twice: as shipped (with the SAMPLE DATA line) and with the flag cleared (must equal the original)
    for (const [pg, tag, clear] of [[L.page, 'legacy', false], [N.page, 'ported', false], [N.page, 'ported-noflag', true]]) {
      await pg.emulateMedia({ media: 'print' });
      if (clear) await pg.evaluate(() => document.body.classList.remove('sample-in-view'));
      const f = `${OUT}/print-${label}-${tag}.pdf`;
      await pg.pdf({ path: f, format: 'A4', printBackground: true }); files.push(f);
    }
    const txt = f => execSync(`pdftotext -layout ${f} -`).toString().replace(/\s+/g, ' ').trim();
    ok(/SAMPLE DATA/.test(txt(files[1])), `print ${label}/${view}: ported report carries the SAMPLE DATA line (sample rows in view)`);
    ok(!/SAMPLE DATA/.test(txt(files[2])), `print ${label}/${view}: flag off removes the line`);
    ok(txt(files[0]) === txt(files[2]), `print ${label}/${view}: printed text identical to the original (same filters)`);
    if (txt(files[0]) !== txt(files[2])) console.log(firstDiff(txt(files[0]), txt(files[2])));
    execSync(`cp ${files[2]} ${OUT}/print-${label}-ported.pdf`);
    execSync(`pdftoppm -r 60 -png -f 1 -l 1 ${files[0]} ${OUT}/pp-${label}-legacy && pdftoppm -r 60 -png -f 1 -l 1 ${files[1]} ${OUT}/pp-${label}-ported`);
    await L.ctx.close(); await N.ctx.close();
  }
}

console.log('\n[11] Download CSV (Admin and Supervisor) and the aligned signatory rows');
{
  const parseCsv = text => { // RFC 4180 parser (quotes, doubled quotes, newlines inside quotes)
    const rows = []; let row = [], cell = '', q = false;
    for (let i = 0; i < text.length; i++) { const c = text[i];
      if (q) { if (c === '"' && text[i + 1] === '"') { cell += '"'; i++; } else if (c === '"') q = false; else cell += c; }
      else if (c === '"') q = true; else if (c === ',') { row.push(cell); cell = ''; }
      else if (c === '\n') { row.push(cell.replace(/\r$/, '')); rows.push(row); row = []; cell = ''; } else cell += c; }
    if (cell || row.length) { row.push(cell); rows.push(row); } return rows; };
  const tricky = Object.assign({}, demo[0], { district: 'Carmen', school: 'Hope, "Central"\nSchool', learningArea: 'SPA - Vocal Arts',
    leastLearned: [{ code: '=1+1', desc: 'plain' }, { code: 'LC-2', desc: '@SUM(A1)' }, { code: 'LC-3', desc: 'x' }, { code: 'LC-4', desc: 'fourth' }] });
  const rowsIn = [demo[0], tricky, demo.find(r => r.district === 'Asuncion' && r.term === 'Term 2'), demo.find(r => r.district === 'Langilan')];
  for (const user of ['admin', 'supervisor']) {
    const N = await openNew(user, rowsIn);
    ok(await N.page.locator('#csv-btn').isVisible(), `${user}: "Download CSV" button is visible`);
    const [dl] = await Promise.all([N.page.waitForEvent('download'), N.page.click('#csv-btn')]);
    const file = `${OUT}/${user}.csv`; await dl.saveAs(file);
    const raw = fs.readFileSync(file, 'utf8'); const rows = parseCsv(raw.replace(/^﻿/, ''));
    ok(/^mapeh-assessment-records-\d{4}-\d{2}-\d{2}\.csv$/.test(dl.suggestedFilename()), `${user}: file name ${dl.suggestedFilename()}`);
    ok(raw.charCodeAt(0) === 0xFEFF, `${user}: UTF-8 byte order mark so Excel reads it correctly`);
    ok(rows.length === 1 + rowsIn.length, `${user}: header plus every record (${rows.length - 1} of ${rowsIn.length} rows)`);
    const h = rows[0];
    const want = ['School Year', 'Term', 'District', 'School Name', 'Key Stage', 'Grade Level', 'Learning Area', 'SY Baseline MPS', 'Mean Percentage Score (MPS%)', '% Learners Scoring >= 75%'];
    ok(want.every((w, i) => h[i] === w), `${user}: columns start with the import template's names, so the file can be re-imported`);
    ok(h.includes('Least Learned Competency 4 Description') && h.includes('Sample Data') && h.includes('Record ID'), `${user}: competency columns expand to the longest list; sample flag and id included`);
    ok(rows.every(r => r.length === h.length), `${user}: every row has exactly ${h.length} columns (quoting is sound)`);
    const t = rows.find(r => r[h.indexOf('Learning Area')] === 'SPA - Vocal Arts');
    ok(t && t[h.indexOf('School Name')] === 'Hope, "Central"\nSchool', `${user}: commas, quotes and line breaks inside a cell round-trip`);
    ok(t && t[h.indexOf('Least Learned Competency 1 Code')] === "'=1+1" && t[h.indexOf('Least Learned Competency 2 Description')] === "'@SUM(A1)", `${user}: text starting with = or @ is neutralised against spreadsheet formulas`);
    const src = rowsIn[0]; const first = rows[1];
    ok(first[h.indexOf('Mean Percentage Score (MPS%)')] === src.mps.toFixed(2) && first[h.indexOf('Proficiency Level')] === src.proficiencyLevel, `${user}: figures written with two decimals and the right level`);
    const order = rows.slice(1).map(r => r[h.indexOf('District')]);
    ok(JSON.stringify(order) === JSON.stringify([...order].sort((a, b) => ['Asuncion', 'B.E. Dujali', 'Carmen', 'Kapalong East', 'Kapalong West', 'New Corella', 'San Isidro', 'Sto. Tomas East', 'Sto. Tomas West', 'Talaingod', 'Langilan'].indexOf(a) - ['Asuncion', 'B.E. Dujali', 'Carmen', 'Kapalong East', 'Kapalong West', 'New Corella', 'San Isidro', 'Sto. Tomas East', 'Sto. Tomas West', 'Talaingod', 'Langilan'].indexOf(b))), `${user}: rows organised by school year, then district order, term, grade`);
    ok(/Downloaded 4 record/.test(await N.page.textContent('#toast-host')), `${user}: confirmation toast reports the count`);
    await N.ctx.close();
  }
  // the whole database, not the current filter
  { const N = await openNew('admin', demo);
    await N.page.selectOption('#flt-district', 'Carmen'); await settled(N.page);
    const [dl] = await Promise.all([N.page.waitForEvent('download'), N.page.click('#csv-btn')]);
    await dl.saveAs(`${OUT}/all.csv`); const rows = parseCsv(fs.readFileSync(`${OUT}/all.csv`, 'utf8').replace(/^﻿/, ''));
    ok(rows.length === 1 + demo.length, `exports the entire data (${rows.length - 1} rows) even while a district filter is active, including the 1,452-row set past the 1,000-row cap`);
    await N.ctx.close(); }
  // coordinators cannot see or use it
  { const N = await openNew('carmen_coord', rowsIn);
    ok(!(await N.page.locator('#csv-btn').isVisible()), 'coordinator: no Download CSV button');
    let got = false; N.page.once('download', () => { got = true; });
    await N.page.evaluate(() => downloadCsv()); await N.page.waitForTimeout(500);
    ok(!got && /Access Denied/.test(await N.page.textContent('#toast-host')), 'coordinator: calling it directly is refused and nothing downloads');
    await N.ctx.close(); }
  // empty database
  { const N = await openNew('admin', []); await N.page.click('#csv-btn');
    ok(/no records to export/i.test(await N.page.textContent('#toast-host')), 'empty database: a clear message instead of an empty file'); await N.ctx.close(); }

  // signatories: three rows, Name and Position in aligned columns
  const A = await openNew('admin', []);
  await A.page.evaluate(() => switchView('settings')); await settled(A.page);
  const box = id => A.page.locator('#' + id).boundingBox();
  const [pn, pp, cn, cp, nn, np] = await Promise.all(['s-pn', 's-pp', 's-cn', 's-cp', 's-nn', 's-np'].map(box));
  ok([[pn, pp], [cn, cp], [nn, np]].every(([a, b]) => Math.abs(a.y - b.y) < 2 && b.x > a.x + a.width), 'signatories: each row has Name then Position side by side');
  ok(Math.abs(pn.x - cn.x) < 2 && Math.abs(cn.x - nn.x) < 2 && Math.abs(pp.x - cp.x) < 2 && Math.abs(cp.x - np.x) < 2, 'signatories: Name inputs share one column and Position inputs share one column');
  ok(pn.y < cn.y && cn.y < nn.y, 'signatories: order is Prepared by, Checked by, Noted by');
  const roles = await A.page.locator('.sig-role').allTextContents();
  ok(JSON.stringify(roles) === JSON.stringify(['Prepared by', 'Checked by', 'Noted by']), 'signatories: row labels');
  await A.page.fill('#s-cn', 'CHECKER NAME'); await A.page.fill('#s-cp', 'Checker Position');
  await A.page.click('button:has-text("Save Division Signatories")'); await A.page.waitForSelector('.toast-success');
  ok(await A.page.evaluate(() => document.getElementById('sig-c-name').textContent === 'CHECKER NAME' && document.getElementById('sig-c-pos').textContent === 'Checker Position'), 'signatories: saving still updates the printed signatory block');
  await A.ctx.close();
}

console.log(`\n${pass} passed, ${fail} failed`);
await browser.close(); server.close();
process.exit(fail ? 1 : 0);
