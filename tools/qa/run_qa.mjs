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
// `demo` is the original combined-area structure: it is what the original app understands, so parity tests use it.
// `demoNew` is the current MAPEH structure (overall + components), used by the component, rule and edit/delete tests.
const demo = JSON.parse(execSync(`python3 ${ROOT}/tools/gen_demo_records.py --legacy --json`, { maxBuffer: 1 << 26 }).toString());
const demoNew = JSON.parse(execSync(`python3 ${ROOT}/tools/gen_demo_records.py --json`, { maxBuffer: 1 << 26 }).toString());
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
const districts = seedRows.map(m => ({ id: Number(m[4]), name: m[1], coordinator_name: m[2], coordinator_position: m[3], elem_coordinator_name: m[2], elem_coordinator_position: m[3], sec_coordinator_name: m[2], sec_coordinator_position: m[3], elem_coordinator_title: '', sec_coordinator_title: '', sort_order: Number(m[4]) }));
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
const CODES = { 'Asuncion': 'asuncion', 'B.E. Dujali': 'dujali', 'Carmen': 'carmen', 'Kapalong East': 'kapalonge', 'Kapalong West': 'kapalongw', 'New Corella': 'newcorella', 'San Isidro': 'sanisidro', 'Sto. Tomas East': 'stotomase', 'Sto. Tomas West': 'stotomasw', 'Talaingod': 'talaingod', 'Langilan': 'langilan' };
const LEVEL_ACCOUNTS = []; // 22 level coordinators: {district_code}_elemcoord / _seccoord, initial password {district_code}@elem / @sec
for (const [district, code] of Object.entries(CODES)) for (const [level, user, pwTag, label] of [['elementary', 'elemcoord', 'elem', 'Elementary'], ['secondary', 'seccoord', 'sec', 'Secondary']])
  LEVEL_ACCOUNTS.push({ username: `${code}_${user}`, password: `${code}@${pwTag}`, district, level, name: `${district} ${label} Coordinator` });
const DIVISION = ACCOUNTS.filter(a => a[2] !== 'district_coordinator');
const profiles = [
  ...DIVISION.map(([username, display_name, role], i) => ({ id: `00000000-0000-0000-0000-${String(i + 1).padStart(12, '0')}`, username, display_name, role, district_id: null, education_level: null, active: true, must_change_password: false })),
  ...LEVEL_ACCOUNTS.map((a, i) => ({ id: `00000000-0000-0000-0001-${String(i + 1).padStart(12, '0')}`, username: a.username, display_name: a.name, role: 'district_coordinator',
    district_id: districts.find(d => d.name === a.district).id, education_level: a.level, active: true, must_change_password: false })),
  // one of the original district-wide coordinators, retired by the migration
  { id: '00000000-0000-0000-0002-000000000001', username: 'carmen_coord', display_name: 'Carmen District Coordinator', role: 'district_coordinator', district_id: 3, education_level: null, active: false, must_change_password: false }
];
const settingsSeed = (() => { // parse supabase/seed/settings.sql json
  const s = fs.readFileSync(path.join(ROOT, 'supabase/seed/settings.sql'), 'utf8');
  return JSON.parse(s.slice(s.indexOf("'{") + 1, s.lastIndexOf("}'") + 1));
})();
const gradeLevelOf = g => ['Grade 1', 'Grade 2', 'Grade 3', 'Grade 4', 'Grade 5', 'Grade 6'].includes(g) ? 'elementary' : 'secondary';
const toRowish = r => ({ education_level: gradeLevelOf(r.gradeLevel), sy: r.sy, term: r.term, district_id: districts.find(d => d.name === r.district).id, school: r.school,
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
  let { passwords: pw } = await readPasswords();
  const ctx = await context('new', viewport); const page = await ctx.newPage();
  const errors = []; page.on('pageerror', e => errors.push(String(e)));
  const allPw = Object.assign({}, pw, Object.fromEntries(LEVEL_ACCOUNTS.map(a => [a.username, a.password])));
  const profs = JSON.parse(JSON.stringify(profiles)).map(p => Object.assign(p, { must_change_password: p.must_change_password || (extra.mustChange || []).includes(p.username) }));
  pw = allPw;
  const stub = { districts: JSON.parse(JSON.stringify(districts)), profiles: profs, passwords: allPw, records: records.map((r, i) => Object.assign({ id: i + 1 }, toRowish(r))),
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
  await page.evaluate(() => { const h = document.getElementById('qa-hide'); if (h) h.remove(); });  // text() hides .screen-only; screen-only views must be visible to be 'settled'
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
const charts = async page => page.evaluate(() => Object.values(activeCharts).slice(0, 2).map(c => c.data.datasets[0].data.map(Number)));

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
    .replace(/(?<![\d.])(?:0\.00%|0%) beginning/g, 'nd')
    // intended label changes of the MAPEH restructure (the legacy records are still counted exactly as before)
    .replace(/\(music & arts \+ pe\)/g, '(overall mapeh)')
    .replace(/consolidated mapeh total \(music & arts \+ pe & health\)/g, 'consolidated mapeh total (overall mapeh)')
    .replace(/tracked specializations \d+ \d+ mapeh,/g, 'tracked specializations N N mapeh,');
}
function canonPorted(t) { return t.toLowerCase().replace(/\s+/g, ' ').trim().replace(/no data no data/g, 'nd').replace(/no data/g, 'nd').replace(/tracked specializations \d+ \d+ mapeh,/g, 'tracked specializations N N mapeh,'); }
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
  ok(profiles.filter(p => p.role !== 'district_coordinator').length === 2 && profiles.filter(p => p.education_level).length === 22 && profiles.filter(p => !p.active).length === 1, 'accounts: Admin and Supervisor kept, 22 level coordinators, the original district-wide coordinators retired');
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
  const N = await openNew('carmen_elemcoord', demo);
  await N.page.evaluate(() => switchView('division')); await settled(N.page);
  let t = await text(N.page);
  ok(t.includes('Carmen') && !t.includes('Asuncion'), 'coordinator sees only own district (Division Summary)');
  ok(await N.page.evaluate(() => document.getElementById('nav-settings').style.display === 'none'), 'Settings & Branding hidden for coordinator');
  await N.page.evaluate(() => switchView('dashboard')); await settled(N.page);
  ok(/TOTAL DISTRICT RECORDS\s+66/i.test(await text(N.page)), 'elementary coordinator sees 66 records: own district and own level only (database filtered)');
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
  ok(await A.page.evaluate(() => window.__STUB.records.filter(r => !r.deleted_at).length === 0 && window.__STUB.records.length === 1452), 'records are hidden from every view but kept in the database (soft delete, recoverable)');
  await A.ctx.close();
}

console.log('\n[6] Writes: confirmed saves, constraint errors, all-or-nothing import, unknown district');
{
  const N = await openNew('admin', demo.slice(0, 20));
  const xlsx = async rows => N.page.evaluate(r => { const ws = XLSX.utils.json_to_sheet(r); const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, ws, 'S'); return Array.from(new Uint8Array(XLSX.write(wb, { type: 'array', bookType: 'xlsx' }))); }, rows);
  const upload = async rows => { await N.page.evaluate(() => switchView('data-input')); await settled(N.page);
    await N.page.setInputFiles('#excel-file', { name: 't.xlsx', mimeType: 'application/octet-stream', buffer: Buffer.from(await xlsx(rows)) }); };
  const base = { 'School Year': '2025-2026', Term: 'Term 1', District: 'Asuncion', 'School Name': 'X', 'Key Stage': 'Key Stage 1', 'Grade Level': 'Grade 1', 'Learning Area': 'MAPEH - Overall', 'SY Baseline MPS': 65, 'Mean Percentage Score (MPS%)': 80, '% Learners Scoring >= 75%': 70, 'Least Learned Competency 1 Description': 'lc one' };
  const count = () => N.page.evaluate(() => window.__STUB.records.length);
  await upload([base, Object.assign({}, base, { District: 'Atlantis' }), Object.assign({}, base, { District: 'Nowhere' })]);
  await N.page.waitForSelector('.toast-error');
  let tmsg = await N.page.textContent('#toast-host');
  ok(/Unknown district in 2 row/.test(tmsg) && /row 3: "Atlantis"/.test(tmsg) && /row 4: "Nowhere"/.test(tmsg), 'unknown district: rejected with row numbers and values');
  ok(await count() === 20, 'unknown district: nothing saved (whole file rejected)');
  await N.page.evaluate(() => document.getElementById('toast-host').innerHTML = '');
  await upload([base, Object.assign({}, base, { 'Mean Percentage Score (MPS%)': 150 })]);
  await N.page.waitForSelector('.toast-error'); tmsg = await N.page.textContent('#toast-host');
  ok(/Nothing was saved\..*row 3: MPS must be between 0 and 100/.test(tmsg), 'MPS 150: plain-English database error, no partial save');
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
  ok(await N.page.evaluate(() => document.querySelectorAll('.nav-item[role=button][tabindex="0"]').length === 10), 'all 10 nav items have role=button and tabindex=0');
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
  for (const [user, label, view, filt] of [['admin', 'division', 'comparative', null], ['admin', 'district', 'comparative', { 'flt-district': 'Carmen' }], ['admin', 'division-dashboard', 'dashboard', null]]) {
    const L = await openLegacy(user, demo); const N = await openNew(user, demo);
    await legacyReady(L.page);
    await goView(L, N, view, filt);
    // hide only the QA-irrelevant banner difference: the ported page has no extra on-screen element in print
    const files = [];
    // ported is printed twice: as shipped (with the SAMPLE DATA line) and with the flag cleared (must equal the original)
    for (const [pg, tag, clear] of [[L.page, 'legacy', false], [N.page, 'ported', false], [N.page, 'ported-noflag', true]]) {
      await pg.emulateMedia({ media: 'print' });
      if (clear) await pg.evaluate(() => document.body.classList.remove('sample-in-view'));
      const f = `${OUT}/print-${label}-${tag}.pdf`;
      await pg.pdf({ path: f, format: 'A4', printBackground: true }); files.push(f);
    }
    const txt = f => execSync(`pdftotext -layout ${f} -`).toString().replace(/\s+/g, ' ').trim().replace(/\(Music & Arts \+ PE & Health\)/g, '(Overall MAPEH)').replace(/\(Music & Arts \+ PE\)/g, '(Overall MAPEH)');
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
  { const N = await openNew('carmen_elemcoord', rowsIn);
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

console.log('\n[12] Elementary and Secondary coordinators: 22 accounts, separation, initial passwords as is');
{
  const LV = { elementary: ['Grade 1', 'Grade 2', 'Grade 3', 'Grade 4', 'Grade 5', 'Grade 6'], secondary: ['Grade 7', 'Grade 8', 'Grade 9', 'Grade 10', 'Grade 11', 'Grade 12'] };
  const LABEL = { elementary: 'Elementary', secondary: 'Secondary' };
  ok(LEVEL_ACCOUNTS.length === 22 && new Set(LEVEL_ACCOUNTS.map(a => a.username)).size === 22, '22 distinct accounts: one Elementary and one Secondary coordinator for each of the 11 districts');
  ok(LEVEL_ACCOUNTS.every(a => /^[a-z]+_(elemcoord|seccoord)$/.test(a.username)), 'usernames follow {district_code}_elemcoord and {district_code}_seccoord');

  // --- every one of the 22 accounts: own district and own level, nothing else
  let allGood = true; const problems = [];
  for (const a of LEVEL_ACCOUNTS) {
    const N = await openNew(a.username, demo);
    const r = await N.page.evaluate(async lvl => {
      await switchView('dashboard');
      const rows = (await sb().from('assessment_records').select('district_id, education_level, grade_level').range(0, 999)).data;
      const own = districtIdByName[currentUser.district];
      return {
        role: document.getElementById('u-role').textContent, rowCount: rows.length,
        onlyOwn: rows.every(x => x.district_id === own && x.education_level === lvl),
        districtLocked: document.getElementById('flt-district').disabled && document.getElementById('flt-district').value === currentUser.district,
        levelLocked: document.getElementById('flt-level').disabled && document.getElementById('flt-level').value === lvl,
        keyStages: Array.from(document.querySelectorAll('#flt-keystage option')).filter(o => !o.disabled).map(o => o.value),
        settingsHidden: document.getElementById('nav-settings').style.display === 'none',
        csvHidden: document.getElementById('csv-btn').style.display === 'none'
      };
    }, a.level);
    const want = a.level === 'elementary' ? ['ALL', 'Key Stage 1', 'Key Stage 2'] : ['ALL', 'Key Stage 3', 'Key Stage 4'];
    const good = r.role === `${LABEL[a.level]} Coordinator (${a.district})` && r.rowCount === 66 && r.onlyOwn && r.districtLocked && r.levelLocked
      && JSON.stringify(r.keyStages) === JSON.stringify(want) && r.settingsHidden && r.csvHidden;
    if (!good) { allGood = false; problems.push(a.username + ' ' + JSON.stringify(r)); }
    await N.ctx.close();
  }
  ok(allGood, 'all 22 accounts: correct label, 66 rows (own district AND level only), district and level locked, own key stages only, no Settings, no CSV' + (problems.length ? ' -> ' + problems[0] : ''));

  // --- an Elementary and a Secondary coordinator of the same district try to cross over
  for (const [user, own, otherLevel, otherGrade, ownGrade] of [['asuncion_elemcoord', 'elementary', 'secondary', 'Grade 8', 'Grade 3'], ['asuncion_seccoord', 'secondary', 'elementary', 'Grade 3', 'Grade 9']]) {
    const N = await openNew(user, demo);
    const att = await N.page.evaluate(async ([og, wg]) => {
      const d = districtIdByName['Asuncion'], other = districtIdByName['Carmen'];
      const row = (district, grade) => ({ sy: '2025-2026', term: 'Term 1', district_id: district, school: '', key_stage: 'Key Stage 1', grade_level: grade, learning_area: 'X', baseline_mps: 65, mps: 80, pct75: 70, proficiency_level: 'x' });
      const out = {};
      out.createOther = (await sb().from('assessment_records').insert(row(d, og))).error?.code;
      out.createOtherDistrict = (await sb().from('assessment_records').insert(row(other, wg))).error?.code;
      out.createUnknownGrade = (await sb().from('assessment_records').insert(row(d, 'Grade 13'))).error?.code;
      const mine = (await sb().from('assessment_records').insert(row(d, wg)).select('id')).data;
      out.createOwn = !!(mine && mine.length === 1);
      out.moveLevel = (await sb().from('assessment_records').update({ grade_level: og }).eq('id', mine[0].id)).error?.code;
      out.moveDistrict = (await sb().from('assessment_records').update({ district_id: other }).eq('id', mine[0].id)).error?.code;
      out.deleteOwn = (await sb().from('assessment_records').delete({ count: 'exact' }).eq('id', mine[0].id)).error?.code;
      out.readOtherLevel = (await sb().from('assessment_records').select('id').eq('education_level', og === 'Grade 8' ? 'secondary' : 'elementary')).data.length;
      out.addRecordHelper = await addRecord({ sy: '2025-2026', term: 'Term 1', district: 'Asuncion', school: '', keyStage: 'Key Stage 1', gradeLevel: og, learningArea: 'X', baselineMps: 65, mps: 80, pct75: 70, proficiencyLevel: 'x', leastLearned: [] }).then(() => 'saved', e => e.code);
      return out;
    }, [otherGrade, ownGrade]);
    ok(att.createOther === '42501' && att.createOtherDistrict === '42501', `${user}: cannot create ${LABEL[otherLevel]} records in its own district, nor anything in another district`);
    ok(att.createUnknownGrade === '23502' || att.createUnknownGrade === '42501', `${user}: an unknown grade level is refused (education level cannot be determined)`);
    ok(att.createOwn && att.moveLevel === '42501' && att.moveDistrict === '42501', `${user}: can create its own, but cannot move a record to the other level or another district`);
    ok(att.deleteOwn === '42501' && att.readOtherLevel === 0, `${user}: cannot hard delete through the API, and reads 0 ${LABEL[otherLevel]} rows even though they exist in the same district`);
    ok(att.addRecordHelper === '42501', `${user}: the app's own save path surfaces the refusal`);
    // the forms only offer this level
    await N.page.evaluate(() => { formDirty = false; switchView('data-input'); }); await settled(N.page);
    await N.page.click('text=Method 2: Fast Manual Entry');
    const grades = await N.page.evaluate(() => Array.from(document.querySelectorAll('#m-grade option')).map(o => o.value));
    ok(JSON.stringify(grades) === JSON.stringify(LV[own]), `${user}: manual entry offers only ${LABEL[own]} grades`);
    // Excel import: one row of the wrong level rejects the whole file, naming the rows
    const xl = rows => N.page.evaluate(r => { const ws = XLSX.utils.json_to_sheet(r); const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, ws, 'S'); return Array.from(new Uint8Array(XLSX.write(wb, { type: 'array', bookType: 'xlsx' }))); }, rows);
    const base = { 'School Year': '2025-2026', Term: 'Term 1', District: 'Asuncion', 'School Name': 'S', 'Key Stage': 'Key Stage 1', 'Grade Level': ownGrade, 'Learning Area': 'MAPEH - Overall', 'SY Baseline MPS': 65, 'Mean Percentage Score (MPS%)': 80, '% Learners Scoring >= 75%': 70, 'Least Learned Competency 1 Description': 'x' };
    const before = await N.page.evaluate(() => window.__STUB.records.length);
    const upload = async rows => { await N.page.evaluate(() => { formDirty = false; switchView('data-input'); }); await settled(N.page); await N.page.evaluate(() => { document.getElementById('toast-host').innerHTML = ''; });
      await N.page.setInputFiles('#excel-file', { name: 't.xlsx', mimeType: 'application/octet-stream', buffer: Buffer.from(await xl(rows)) }); };
    await upload([base, { ...base, 'Grade Level': otherGrade }, { ...base, 'Grade Level': 'Grade 99' }]);
    await N.page.waitForSelector('.toast-error'); const msg = await N.page.textContent('#toast-host');
    ok(new RegExp(`only import ${LABEL[own]} records`).test(msg) && /row 3/.test(msg) && /row 4/.test(msg) && (await N.page.evaluate(() => window.__STUB.records.length)) === before, `${user}: an import with other-level or unknown grades is rejected with row numbers and saves nothing`);
    await upload([base, { ...base, Term: 'Term 2' }]); await N.page.waitForSelector('.toast-success');
    ok((await N.page.evaluate(() => window.__STUB.records.length)) === before + 2, `${user}: an import of its own level is saved`);
    await N.ctx.close();
  }

  // --- client decision (testing phase): initial passwords are used as is; there is no change-password screen
  for (const u of ['dujali_seccoord', 'langilan_elemcoord']) {
    const a = LEVEL_ACCOUNTS.find(x => x.username === u);
    const N = await openNew(u, demo, { noLogin: true });
    await N.page.fill('#login-username', u); await N.page.fill('#login-password', a.password); await N.page.click('#login-screen button[type=submit]');
    await N.page.waitForFunction(() => document.getElementById('login-screen').style.display === 'none'); await settled(N.page);
    ok(await N.page.locator('#pw-modal').count() === 0 && await N.page.locator('.user-profile-badge button:has-text("Password")').count() === 0, `${u}: signs in with the initial password straight into the app; no change-password screen or button exists`);
    ok(await N.page.evaluate(() => currentUser.district !== 'ALL' && currentUser.educationLevel !== 'ALL' && !!document.querySelector('#view-container .kpi-grid')), `${u}: data screens open, still limited to own district and level`);
    ok(await N.page.evaluate(() => (typeof requestPasswordChange === 'undefined') && window.APP_CONFIG.features.selfServicePassword !== true), `${u}: the password-change code is gone`);
    await N.ctx.close();
  }

  // --- the original district-wide coordinators are retired
  {
    const N = await openNew('carmen_coord', demo, { noLogin: true });
    const { passwords: pw } = await readPasswords();
    await N.page.fill('#login-username', 'carmen_coord'); await N.page.fill('#login-password', pw.carmen_coord); await N.page.click('#login-screen button[type=submit]');
    await N.page.waitForFunction(() => /retired/i.test(document.getElementById('login-error').textContent));
    ok(await N.page.evaluate(() => document.getElementById('login-screen').style.display !== 'none' && !sessionStorage.getItem('stub_session')), 'a retired district-wide coordinator account is signed out with a clear message and sees nothing');
    await N.ctx.close();
  }

  // --- Admin and Supervisor: both levels, with an Education Level filter
  for (const user of ['admin', 'supervisor']) {
    const N = await openNew(user, demo);
    ok(await N.page.evaluate(() => !document.getElementById('flt-level').disabled && document.getElementById('flt-level').value === 'ALL'), `${user}: Education Level filter is free (All Levels)`);
    await N.page.evaluate(() => switchView('dashboard')); await settled(N.page);
    ok(/TOTAL DISTRICT RECORDS\s+1452/i.test(await text(N.page)), `${user}: sees both levels (1452 records)`);
    await N.page.selectOption('#flt-level', 'elementary'); await settled(N.page);
    ok(/TOTAL DISTRICT RECORDS\s+726/i.test(await text(N.page)), `${user}: Elementary filter shows 726 records`);
    ok(JSON.stringify(await N.page.evaluate(() => Array.from(document.querySelectorAll('#flt-keystage option')).filter(o => !o.disabled).map(o => o.value))) === JSON.stringify(['ALL', 'Key Stage 1', 'Key Stage 2']), `${user}: key stages narrow to the chosen level`);
    ok(await N.page.evaluate(() => document.getElementById('print-title').textContent.includes('ELEMENTARY')), `${user}: the printed report title names the level`);
    await N.page.evaluate(() => switchView('grade-view')); await settled(N.page);
    ok((await N.page.locator('#view-container table.data-table tbody tr').count()) === 6, `${user}: grade level breakdown shows Grades 1 to 6 only`);
    await N.page.evaluate(() => switchView('comparative')); await settled(N.page);
    ok((await N.page.locator('.editable-baseline-input').count()) === 2, `${user}: comparative analysis shows the two Elementary key stages`);
    await N.page.selectOption('#flt-level', 'secondary'); await settled(N.page);
    await N.page.evaluate(() => switchView('dashboard')); await settled(N.page);
    ok(/TOTAL DISTRICT RECORDS\s+726/i.test(await text(N.page)), `${user}: Secondary filter shows the other 726`);
    const [dl] = await Promise.all([N.page.waitForEvent('download'), N.page.click('#csv-btn')]);
    await dl.saveAs(`${OUT}/levels-${user}.csv`); const lines = fs.readFileSync(`${OUT}/levels-${user}.csv`, 'utf8').replace(/^﻿/, '').trim().split(/\r?\n/);
    const hdr = lines[0].split(','); const li = hdr.indexOf('Education Level');
    const lv = new Set(lines.slice(1).map(l => l.split(',')[li]));
    ok(li > 0 && lines.length === 1453 && lv.has('Elementary') && lv.has('Secondary'), `${user}: the CSV is the entire data (1452 rows, both levels) with an Education Level column`);
    await N.ctx.close();
  }

  // --- notes are filed per district and level; the secondary template matches the level
  {
    const N = await openNew('asuncion_seccoord', demo);
    await N.page.evaluate(() => switchView('comparative')); await settled(N.page);
    await N.page.fill('#comp-analysis-input', 'secondary note'); await N.page.click('text=Save Qualitative Notes'); await N.page.waitForSelector('.toast-success');
    const n = await N.page.evaluate(() => window.__STUB.notes.map(x => [x.district_scope, x.education_level]));
    ok(JSON.stringify(n) === JSON.stringify([['Asuncion', 'secondary']]), 'notes are saved under the coordinator\'s district AND level');
    ok((await N.page.locator('.editable-baseline-input').count()) === 2, 'a Secondary coordinator sees only Key Stages 3 and 4 in the comparative table');
    await N.page.evaluate(() => { formDirty = false; switchView('data-input'); }); await settled(N.page);
    const [dl] = await Promise.all([N.page.waitForEvent('download'), N.page.click('text=Download Excel Template')]);
    ok(/_Secondary\.xlsx$/.test(dl.suggestedFilename()), 'the Excel template is the Secondary template (' + dl.suggestedFilename() + ')');
    await N.ctx.close();
  }
}


console.log('\n[16] MAPEH components, grade rules, and record edit / delete');
{
  const mean = a => a.reduce((x, y) => x + y, 0) / a.length;
  const f2 = v => v.toFixed(2) + '%';
  const meanOf = f => mean(demoNew.filter(f).map(r => r.mps));
  const termMean = (f) => { const tm = ['Term 1', 'Term 2', 'Term 3'].map(t => demoNew.filter(r => r.term === t && f(r)).map(r => r.mps)).filter(a => a.length).map(mean); return mean(tm); };
  const cardRows = (page, title) => page.evaluate(t => {
    const card = Array.from(document.querySelectorAll('#view-container .card-box')).find(c => (c.querySelector('h3') || {}).textContent.includes(t));
    return card ? Array.from(card.querySelectorAll('tbody tr')).map(tr => Array.from(tr.children).map(td => td.innerText.replace(/\s+/g, ' ').trim())) : null;
  }, title);

  // ---- component breakdown
  {
    const N = await openNew('admin', demoNew);
    await N.page.evaluate(() => switchView('grade-view')); await settled(N.page);
    const g = await cardRows(N.page, 'MAPEH Components by Grade Level');
    ok(!!g && g.length === 13, 'Grade Level Breakdown has the component table (12 grades + all-grades row)');
    const g4 = g.find(r => r[0] === 'Grade 4'), g1 = g.find(r => r[0] === 'Grade 1'), g11 = g.find(r => r[0] === 'Grade 11');
    ok(g4[1].startsWith(f2(meanOf(r => r.gradeLevel === 'Grade 4' && r.learningArea === 'MAPEH - Music'))) && g4[2].startsWith(f2(meanOf(r => r.gradeLevel === 'Grade 4' && r.learningArea === 'MAPEH - Arts')))
      && g4[3].startsWith(f2(meanOf(r => r.gradeLevel === 'Grade 4' && r.learningArea === 'MAPEH - PE'))) && g4[4].startsWith(f2(meanOf(r => r.gradeLevel === 'Grade 4' && r.learningArea === 'MAPEH - Health'))), 'Grade 4: Music, Arts, PE and Health MPS shown separately and correct');
    const ov4 = meanOf(r => r.gradeLevel === 'Grade 4' && r.learningArea === 'MAPEH - Overall');
    const avgParts = mean(['Music', 'Arts', 'PE', 'Health'].map(c => meanOf(r => r.gradeLevel === 'Grade 4' && r.learningArea === 'MAPEH - ' + c)));
    ok(g4[5].startsWith(f2(ov4)) && f2(ov4) !== f2(avgParts), 'Grade 4: Overall MAPEH is the official record (' + f2(ov4) + '), not the average of the components (' + f2(avgParts) + ')');
    ok(g1[1].includes('Not recorded') && g1[4].includes('Not recorded') && g1[5].startsWith(f2(meanOf(r => r.gradeLevel === 'Grade 1' && r.learningArea === 'MAPEH - Overall'))), 'Grade 1: components not recorded, overall MAPEH only');
    ok(g11.slice(1, 6).every(c => c.includes('Not recorded')), 'Grade 11: no MAPEH');
    await N.page.evaluate(() => switchView('division')); await settled(N.page);
    const d = await cardRows(N.page, 'MAPEH Components by District');
    const asu = d.find(r => r[1] === 'Asuncion');
    ok(!!d && asu[2].startsWith(f2(termMean(r => r.district === 'Asuncion' && r.learningArea === 'MAPEH - Music'))) && asu[6].startsWith(f2(termMean(r => r.district === 'Asuncion' && r.learningArea === 'MAPEH - Overall'))), 'Division Summary: district component table (mean of term means) matches');
    await N.page.evaluate(() => switchView('dashboard')); await settled(N.page);
    const ch = await N.page.evaluate(() => Object.values(activeCharts).map(c => [c.data.labels, c.data.datasets[0].data]));
    ok(ch.length === 3 && JSON.stringify(ch[2][0]) === JSON.stringify(['Music', 'Arts', 'Physical Education (PE)', 'Health', 'Overall MAPEH']) && Math.abs(ch[2][1][4] - meanOf(r => r.learningArea === 'MAPEH - Overall')) < 0.006, 'Dashboard: MAPEH components chart with the overall as its own bar');
    ok(new RegExp('MAPEH Consolidated Total MPS\\s+' + meanOf(r => r.learningArea === 'MAPEH - Overall').toFixed(2) + '%', 'i').test(await text(N.page)), 'Dashboard MAPEH total = official overall records only (components are not double counted)');
    await N.page.evaluate(() => switchView('comparative')); await settled(N.page);
    const ct = await text(N.page);
    ok(/MAPEH component: Music/.test(ct) && /MAPEH component: Physical Education \(PE\)/.test(ct) && /CONSOLIDATED MAPEH TOTAL \(Overall MAPEH\)/.test(ct), 'Comparative sheet: component rows under the MAPEH total');
    await N.page.evaluate(() => { resetFilters(); switchView('district-view'); }); await settled(N.page);
    ok(/MAPEH - Health/.test(await text(N.page)), 'District Profile lists the new MAPEH areas as subject rows');
    ok(N.errors.length === 0, 'no page errors while rendering the component views' + (N.errors[0] ? ': ' + N.errors[0] : ''));
    await N.ctx.close();
  }

  // ---- grade rules: forms, imports, and the backend
  {
    const N = await openNew('admin', demoNew.slice(0, 20));
    await N.page.evaluate(() => switchView('data-input')); await settled(N.page);
    await N.page.click('text=Method 2: Fast Manual Entry');
    const opts = async g => { await N.page.selectOption('#m-grade', g); return N.page.evaluate(() => Array.from(document.querySelectorAll('#m-subject option')).map(o => o.value)); };
    const o1 = await opts('Grade 2'), o5 = await opts('Grade 5'), o11 = await opts('Grade 11');
    ok(o1.includes('MAPEH - Overall') && !o1.some(v => /MAPEH - (Music|Arts|PE|Health)/.test(v)) && o1.includes('IPED - English'), 'manual entry Grade 2: overall MAPEH only (no components, no combined areas); IPED untouched');
    ok(['MAPEH - Overall', 'MAPEH - Music', 'MAPEH - Arts', 'MAPEH - PE', 'MAPEH - Health'].every(v => o5.includes(v)) && !o5.some(v => /&/.test(v) && /^MAPEH/.test(v)), 'manual entry Grade 5: overall plus four components, no combined areas');
    ok(!o11.some(v => /^MAPEH/.test(v)) && o11.includes('SPA - Vocal Arts'), 'manual entry Grade 11: no MAPEH areas');
    const filterOpts = await N.page.evaluate(() => Array.from(document.querySelectorAll('#flt-subject option')).map(o => o.value));
    ok(filterOpts.includes('MAPEH - Music') && filterOpts.includes('MAPEH - Music & Arts'), 'the subject filter lists new areas and still lists the legacy ones');

    const xlsx = async rows => N.page.evaluate(r => { const ws = XLSX.utils.json_to_sheet(r); const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, ws, 'S'); return Array.from(new Uint8Array(XLSX.write(wb, { type: 'array', bookType: 'xlsx' }))); }, rows);
    const upload = async rows => { await N.page.evaluate(() => { formDirty = false; switchView('data-input'); }); await settled(N.page); await N.page.evaluate(() => { document.getElementById('toast-host').innerHTML = ''; });
      await N.page.setInputFiles('#excel-file', { name: 't.xlsx', mimeType: 'application/octet-stream', buffer: Buffer.from(await xlsx(rows)) }); };
    const base = { 'School Year': '2025-2026', Term: 'Term 1', District: 'Asuncion', 'School Name': 'X', 'Key Stage': 'Key Stage 1', 'Grade Level': 'Grade 1', 'Learning Area': 'MAPEH - Overall', 'SY Baseline MPS': 65, 'Mean Percentage Score (MPS%)': 80, '% Learners Scoring >= 75%': 70, 'Least Learned Competency 1 Description': 'lc' };
    const count = () => N.page.evaluate(() => window.__STUB.records.length);
    const bad = [['Grade 2', 'MAPEH - Music'], ['Grade 3', 'MAPEH - Health'], ['Grade 1', 'MAPEH - Music & Arts'], ['Grade 5', 'MAPEH - PE & Health'], ['Grade 11', 'MAPEH - Overall'], ['Grade 12', 'MAPEH - Arts']];
    for (const [gr, area] of bad) {
      await upload([base, Object.assign({}, base, { 'Grade Level': gr, 'Learning Area': area })]);
      await N.page.waitForSelector('.toast-error');
      const m = await N.page.textContent('#toast-host');
      ok(/Nothing was saved/.test(m) && /row 3/.test(m) && await count() === 20, `import refuses ${gr} / ${area} with its row number, and saves nothing (the valid row 2 is not saved either)`);
    }
    await upload([Object.assign({}, base, { 'Grade Level': 'Grade 2', 'Learning Area': 'IPED - MAPEH (Music & Arts)' }), Object.assign({}, base, { 'Grade Level': 'Grade 5', 'Key Stage': 'Key Stage 2', 'Learning Area': 'MAPEH - Music' }), Object.assign({}, base, { 'Grade Level': 'Grade 9', 'Key Stage': 'Key Stage 3', 'Learning Area': 'MAPEH - Overall' })]);
    await N.page.waitForSelector('.toast-success');
    ok(await count() === 23, 'import accepts IPED in Grade 2 (unrestricted), Music in Grade 5 and Overall in Grade 9');
    // the backend refuses the same combinations when the app is bypassed
    const api = await N.page.evaluate(async () => {
      const row = (g, a) => ({ sy: '2025-2026', term: 'Term 1', district_id: 1, school: '', key_stage: 'Key Stage 1', grade_level: g, learning_area: a, baseline_mps: 65, mps: 80, pct75: 70, proficiency_level: 'x' });
      const r = {};
      r.g1music = (await sb().from('assessment_records').insert(row('Grade 1', 'MAPEH - Music'))).error;
      r.g4legacy = (await sb().from('assessment_records').insert(row('Grade 4', 'MAPEH - Music & Arts'))).error;
      r.g12 = (await sb().from('assessment_records').insert(row('Grade 12', 'MAPEH - Overall'))).error;
      r.iped = (await sb().from('assessment_records').insert(row('Grade 1', 'IPED - MAPEH (PE & Health)'))).error;
      const id = (await sb().from('assessment_records').insert(row('Grade 5', 'MAPEH - Music')).select('id')).data[0].id;
      r.move = (await sb().from('assessment_records').update({ grade_level: 'Grade 2' }).eq('id', id)).error;
      r.msg = friendlyError(r.g1music);
      return r;
    });
    ok(api.g1music?.code === '23514' && api.g4legacy?.code === '23514' && api.g12?.code === '23514' && api.iped === null && api.move?.code === '23514', 'backend refuses Grade 1 Music, Grade 4 legacy, Grade 12 MAPEH and editing Music into Grade 2; IPED passes');
    ok(/^Grades 1 to 3 are recorded as overall MAPEH only/.test(api.msg), 'the backend rule is shown in plain English');
    await N.ctx.close();
  }

  // ---- templates follow the rules
  for (const user of ['asuncion_elemcoord', 'asuncion_seccoord']) {
    const N = await openNew(user, demoNew);
    const rows = await N.page.evaluate(() => { let got = null; XLSX.writeFile = wb => { got = XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]]); }; downloadExcelTemplate(); return got.map(r => [r['Grade Level'], r['Learning Area'], mapehRuleProblem(r['Grade Level'], r['Learning Area'])]); });
    ok(rows.length >= 2 && rows.every(r => r[2] === ''), `${user}: every template example row passes the MAPEH rules`);
    await N.ctx.close();
  }

  // ---- Manage Records: edit
  const asuG4 = demoNew.findIndex(r => r.district === 'Asuncion' && r.gradeLevel === 'Grade 4' && r.learningArea === 'MAPEH - Music' && r.term === 'Term 1') + 1;
  const legacyRec = Object.assign({}, demoNew[0], { district: 'Asuncion', gradeLevel: 'Grade 2', keyStage: 'Key Stage 1', learningArea: 'MAPEH - Music & Arts', school: '' });
  const withLegacy = demoNew.concat([legacyRec]);
  const legacyId = withLegacy.length;
  {
    const N = await openNew('admin', withLegacy);
    const total = withLegacy.length;
    await N.page.evaluate(() => switchView('manage-records')); await settled(N.page);
    ok(await N.page.locator('#mr-tab-deleted').count() === 1 && /of 1[0-9]{3}/.test(await N.page.textContent('#mr-pager')), 'Manage Records: admin sees every record and the Deleted records tab');
    await N.page.fill('#mr-search', 'MAPEH - Music &');
    const flagged = await N.page.textContent('#mr-table');
    ok(/Needs correction/.test(flagged) && /of 1\b/.test(await N.page.textContent('#mr-pager')), 'search narrows the list; a Grade 2 legacy record is flagged "Needs correction"');
    // edit legacy record: score only (old area stays allowed because grade and area did not change)
    await N.page.evaluate(id => openRecordEditor(id), legacyId);
    await N.page.fill('#e-mps', '91.5'); await N.page.click('#rec-save');
    await N.page.waitForSelector('.toast-success');
    let rec = await N.page.evaluate(id => window.__STUB.records.find(r => r.id === id), legacyId);
    ok(rec.mps === 91.5 && rec.proficiency_level === 'Advanced' && rec.learning_area === 'MAPEH - Music & Arts' && !!rec.updated_by, 'editing only the score of a legacy Grade 2 record saves; proficiency is recomputed by the database; editor is stamped');
    // edit into a forbidden combination: Grade 4 Music -> Grade 2
    await N.page.evaluate(id => openRecordEditor(id), asuG4);
    await N.page.selectOption('#e-grade', 'Grade 2'); await N.page.selectOption('#e-subject', 'MAPEH - Music'); await N.page.click('#rec-save');
    ok(/Grades 1 to 3 are recorded as overall MAPEH only/.test(await N.page.textContent('#rec-error')) && (await N.page.evaluate(id => window.__STUB.records.find(r => r.id === id).grade_level, asuG4)) === 'Grade 4', 'edit form refuses Music for Grade 2 before saving');
    await N.page.selectOption('#e-grade', 'Grade 4'); await N.page.selectOption('#e-subject', 'MAPEH - Music');
    await N.page.fill('#e-mps', '120'); await N.page.click('#rec-save');
    ok(/MPS must be between 0 and 100/.test(await N.page.textContent('#rec-error')), 'edit form revalidates ranges');
    await N.page.fill('#e-mps', '93.25'); await N.page.fill('#e-school', 'Edited School'); await N.page.click('#rec-save');
    await N.page.waitForSelector('.toast-success');
    rec = await N.page.evaluate(id => window.__STUB.records.find(r => r.id === id), asuG4);
    ok(rec.mps === 93.25 && rec.school === 'Edited School' && rec.proficiency_level === 'Advanced', 'a valid edit is saved and confirmed by the database');
    // the edit is visible in the reports
    await N.page.evaluate(() => { formDirty = false; switchView('grade-view'); }); await settled(N.page);
    const g = await cardRows(N.page, 'MAPEH Components by Grade Level');
    const newMean = mean(demoNew.map((r, i) => ({ r, mps: i + 1 === asuG4 ? 93.25 : r.mps })).filter(x => x.r.gradeLevel === 'Grade 4' && x.r.learningArea === 'MAPEH - Music').map(x => x.mps));
    ok(g.find(r => r[0] === 'Grade 4')[1].startsWith(f2(newMean)), 'Grade Level Breakdown reflects the edited record (' + f2(newMean) + ')');
    // backend: direct edit of an out-of-range value
    const e = await N.page.evaluate(async id => (await sb().from('assessment_records').update({ mps: 101 }).eq('id', id)).error?.code, asuG4);
    ok(e === '23514', 'backend refuses mps 101 on a direct edit');

    // delete: cancel first, then confirm
    await N.page.evaluate(() => switchView('manage-records')); await settled(N.page);
    await N.page.evaluate(id => openRecordDelete(id), asuG4);
    await N.page.click('#record-modal .btn-secondary');
    ok(await N.page.evaluate(id => !window.__STUB.records.find(r => r.id === id).deleted_at, asuG4), 'cancelling the delete changes nothing');
    await N.page.evaluate(id => openRecordDelete(id), asuG4);
    await N.page.fill('#del-reason', 'entered by mistake'); await N.page.click('#rec-confirm-delete');
    await N.page.waitForSelector('.toast-success');
    rec = await N.page.evaluate(id => window.__STUB.records.find(r => r.id === id), asuG4);
    ok(!!rec.deleted_at && rec.delete_reason === 'entered by mistake' && !!rec.deleted_by && await N.page.evaluate(() => window.__STUB.records.length) === total, 'delete is soft: the row stays, with who, when and why');
    await N.page.evaluate(() => { switchView('dashboard'); }); await settled(N.page);
    ok(new RegExp('TOTAL DISTRICT RECORDS\\s+' + (total - 1) + '\\b', 'i').test(await text(N.page)), 'dashboards no longer count the deleted record');
    await N.page.evaluate(() => switchView('grade-view')); await settled(N.page);
    const g2 = await cardRows(N.page, 'MAPEH Components by Grade Level');
    const afterMean = mean(demoNew.filter((r, i) => r.gradeLevel === 'Grade 4' && r.learningArea === 'MAPEH - Music' && i + 1 !== asuG4).map(r => r.mps));
    ok(g2.find(r => r[0] === 'Grade 4')[1].startsWith(f2(afterMean)), 'reports exclude the deleted record');
    await N.page.evaluate(() => switchView('manage-records')); await settled(N.page);
    await N.page.click('#mr-tab-deleted'); await N.page.waitForFunction(() => /Deleted Assessment Records/.test(document.getElementById('mr-title').textContent));
    ok(/entered by mistake/.test(await N.page.textContent('#mr-table')), 'Deleted records tab lists it with the reason');
    N.page.on('dialog', d => d.accept());
    await N.page.click('#mr-table button:has-text("Restore")'); await N.page.waitForSelector('.toast-success');
    ok(await N.page.evaluate(id => !window.__STUB.records.find(r => r.id === id).deleted_at, asuG4), 'Restore brings the record back');
    await N.ctx.close();
  }

  // ---- permissions: coordinators and direct API requests
  {
    const N = await openNew('asuncion_elemcoord', demoNew);
    const ownN = demoNew.filter(r => r.district === 'Asuncion' && ['Grade 1', 'Grade 2', 'Grade 3', 'Grade 4', 'Grade 5', 'Grade 6'].includes(r.gradeLevel)).length;
    await N.page.evaluate(() => switchView('manage-records')); await settled(N.page);
    ok(new RegExp('of ' + ownN + '\\b').test(await N.page.textContent('#mr-pager')) && await N.page.locator('#mr-tab-deleted').count() === 0, `coordinator: Manage Records lists only own district and level (${ownN}) and has no Deleted tab`);
    const ids = {
      own: demoNew.findIndex(r => r.district === 'Asuncion' && r.gradeLevel === 'Grade 4' && r.learningArea === 'MAPEH - Arts' && r.term === 'Term 1') + 1,
      ownB: demoNew.findIndex(r => r.district === 'Asuncion' && r.gradeLevel === 'Grade 4' && r.learningArea === 'MAPEH - Health' && r.term === 'Term 1') + 1,
      otherLevel: demoNew.findIndex(r => r.district === 'Asuncion' && r.gradeLevel === 'Grade 8' && r.term === 'Term 1') + 1,
      otherDist: demoNew.findIndex(r => r.district === 'Carmen' && r.gradeLevel === 'Grade 4' && r.term === 'Term 1') + 1
    };
    await N.page.evaluate(id => openRecordEditor(id), ids.own);
    ok(await N.page.evaluate(() => document.getElementById('e-district').disabled && Array.from(document.querySelectorAll('#e-grade option')).every(o => ['Grade 1', 'Grade 2', 'Grade 3', 'Grade 4', 'Grade 5', 'Grade 6'].includes(o.value))), 'coordinator edit form: district locked, only own-level grades offered');
    await N.page.fill('#e-mps', '82'); await N.page.click('#rec-save'); await N.page.waitForSelector('.toast-success');
    ok(await N.page.evaluate(id => window.__STUB.records.find(r => r.id === id).mps, ids.own) === 82, 'coordinator can edit a record in scope');
    const a = await N.page.evaluate(async ids => {
      const r = {}, T = () => window.__STUB.records;
      r.editOther = (await sb().from('assessment_records').update({ mps: 1 }).eq('id', ids.otherDist).select('id')).data.length;
      r.editOtherLevel = (await sb().from('assessment_records').update({ mps: 1 }).eq('id', ids.otherLevel).select('id')).data.length;
      r.rpcOtherDist = (await sb().rpc('app_delete_records', { p_ids: [ids.otherDist] })).error?.code;
      r.rpcOtherLevel = (await sb().rpc('app_delete_records', { p_ids: [ids.otherLevel] })).error?.code;
      r.rpcMixed = (await sb().rpc('app_delete_records', { p_ids: [ids.own, ids.otherDist] })).error?.code;
      r.mixedUntouched = !T().find(x => x.id === ids.own).deleted_at;
      r.hardDelete = (await sb().from('assessment_records').delete().eq('id', ids.own)).error?.code;
      r.setDeleted = (await sb().from('assessment_records').update({ deleted_at: '2020-01-01' }).eq('id', ids.own)).error?.code;
      r.setDemo = (await sb().from('assessment_records').update({ is_demo: true }).eq('id', ids.own)).error?.code;
      r.setOwner = (await sb().from('assessment_records').update({ created_by: '00000000-0000-0000-0000-000000000001' }).eq('id', ids.own)).error?.code;
      r.bulkSy = (await sb().rpc('app_delete_records_by_sy', { p_sy: '2025-2026' })).error?.code;
      r.bulkAll = (await sb().rpc('app_delete_all_records')).error?.code;
      r.restore = (await sb().rpc('app_restore_records', { p_ids: [ids.own] })).error?.code;
      r.delOwn = (await sb().rpc('app_delete_records', { p_ids: [ids.ownB], p_reason: 'api' })).data;
      r.seeDeleted = (await sb().from('assessment_records').select('id').eq('id', ids.ownB)).data.length;
      r.seeDeletedList = (await sb().from('assessment_records').select('id').not('deleted_at', 'is', null)).data.length;
      r.editDeleted = (await sb().from('assessment_records').update({ mps: 5 }).eq('id', ids.ownB).select('id')).data.length;
      r.unchanged = T().find(x => x.id === ids.otherDist).mps !== 1 && T().find(x => x.id === ids.otherLevel).mps !== 1;
      return r;
    }, ids);
    ok(a.editOther === 0 && a.editOtherLevel === 0 && a.unchanged, 'coordinator direct edit of another district or the other level changes nothing');
    ok(a.rpcOtherDist === '42501' && a.rpcOtherLevel === '42501' && a.rpcMixed === '42501' && a.mixedUntouched, 'coordinator delete outside scope is refused, and a batch with one bad id deletes nothing');
    ok(a.hardDelete === '42501' && a.setDeleted === '42501' && a.setDemo === '42501' && a.setOwner === '42501', 'direct API cannot hard delete, set deleted_at, or rewrite is_demo / created_by');
    ok(a.bulkSy === '42501' && a.bulkAll === '42501' && a.restore === '42501', 'coordinator cannot bulk delete or restore');
    ok(a.delOwn === 1 && a.seeDeleted === 0 && a.seeDeletedList === 0 && a.editDeleted === 0, 'coordinator can delete in scope; the deleted record disappears for them and cannot be edited');
    await N.ctx.close();
    const S = await openNew('supervisor', demoNew);
    await S.page.evaluate(() => { window.__STUB.records.find(r => r.id === 5).deleted_at = '2026-01-01T00:00:00Z'; switchView('manage-records'); }); await settled(S.page);
    await S.page.click('#mr-tab-deleted'); await S.page.waitForFunction(() => /Deleted Assessment Records/.test(document.getElementById('mr-title').textContent));
    ok(await S.page.locator('#mr-table button:has-text("Restore")').count() === 1, 'supervisor sees deleted records and can restore them');
    await S.ctx.close();
  }
}


console.log('\n[17] Settings: coordinators grouped by district, one Elementary and one Secondary each');
{
  const N = await openNew('admin', demo.slice(0, 40));
  await N.page.evaluate(() => switchView('settings')); await settled(N.page);
  const cards = await N.page.evaluate(() => Array.from(document.querySelectorAll('.coord-card')).map(c => ({
    h: c.querySelector('h5').textContent.trim(),
    subs: Array.from(c.querySelectorAll('.coord-sub')).map(x => ({ t: x.querySelector('h6').textContent.trim(), n: x.querySelectorAll('input').length, v: Array.from(x.querySelectorAll('input')).map(i => i.value) }))
  })));
  ok(cards.length === 11 && cards.every((c, i) => c.h === `${i + 1}. ${districts[i].name} District`), 'one card per district, in the existing district order (11)');
  ok(cards.every(c => c.subs.length === 2 && c.subs[0].t === 'Elementary Coordinator' && c.subs[1].t === 'Secondary Coordinator' && c.subs.every(x => x.n === 3)), 'each district holds an Elementary and a Secondary subsection directly beneath it, with Name, Designated Position and Title as separate fields');
  ok(cards.every((c, i) => c.subs.every(x => x.v[0] === districts[i].coordinator_name && x.v[1] === districts[i].coordinator_position && x.v[2] === '')), 'existing coordinator information is preserved in both subsections (position kept, title starts empty)');
  ok(await N.page.evaluate(() => document.querySelectorAll('label[for^="coord-"]').length === 66 && Array.from(document.querySelectorAll('label[for^="coord-"]')).every(l => document.getElementById(l.htmlFor))), 'all 66 fields are labelled (Coordinator Name, Designated Position, Title)');
  // edit Asuncion: different details per level; Carmen untouched
  await N.page.fill('#coord-e-name-Asuncion', 'Elena Elementary'); await N.page.fill('#coord-e-pos-Asuncion', 'Elementary Supervisor'); await N.page.fill('#coord-e-title-Asuncion', 'Principal II');
  await N.page.fill('#coord-s-name-Asuncion', 'Sam Secondary'); await N.page.fill('#coord-s-pos-Asuncion', 'Secondary Principal');
  await N.page.click('text=Save District Coordinators'); await N.page.waitForSelector('.toast-success');
  const st = await N.page.evaluate(() => window.__STUB.districts.map(d => [d.name, d.elem_coordinator_name, d.elem_coordinator_position, d.sec_coordinator_name, d.sec_coordinator_position, d.elem_coordinator_title, d.sec_coordinator_title]));
  ok(JSON.stringify(st[0]) === JSON.stringify(['Asuncion', 'Elena Elementary', 'Elementary Supervisor', 'Sam Secondary', 'Secondary Principal', 'Principal II', '']) && st[2][1] === districts[2].coordinator_name && st[2][3] === districts[2].coordinator_name, 'each level is stored separately (four columns); other districts unchanged');
  ok(await N.page.evaluate(() => document.getElementById('coord-e-name-Asuncion').value === 'Elena Elementary' && document.getElementById('coord-s-name-Asuncion').value === 'Sam Secondary'), 'the form reloads what the database holds');

  // reports use the coordinator of the level shown
  const sig = async () => N.page.evaluate(() => [document.getElementById('sig-p-name').textContent, document.getElementById('sig-p-pos').textContent]);
  await N.page.evaluate(() => { resetFilters(); switchView('district-view'); }); await settled(N.page);
  await N.page.selectOption('#flt-district', 'Asuncion'); await settled(N.page);
  await N.page.selectOption('#flt-level', 'elementary'); await settled(N.page);
  ok(JSON.stringify(await sig()) === JSON.stringify(['Elena Elementary', 'Asuncion Elementary Supervisor, Principal II']), 'report signatory (Elementary view) = the Elementary coordinator: position, then title');
  ok((await N.page.textContent('#view-container')).includes('Elena Elementary') && !(await N.page.textContent('#view-container')).includes('Sam Secondary'), 'District Profile shows the Elementary coordinator only');
  await N.page.selectOption('#flt-level', 'secondary'); await settled(N.page);
  ok(JSON.stringify(await sig()) === JSON.stringify(['Sam Secondary', 'Asuncion Secondary Principal']), 'report signatory (Secondary view) = the Secondary coordinator');
  await N.page.selectOption('#flt-level', 'ALL'); await settled(N.page);
  ok(JSON.stringify(await sig()) === JSON.stringify(['Elena Elementary / Sam Secondary', 'Asuncion Elementary Supervisor, Principal II / Secondary Principal']), 'both levels in view and the details differ: both coordinators are named');
  await N.page.evaluate(() => { resetFilters(); switchView('division'); }); await settled(N.page);
  await N.page.selectOption('#flt-level', 'secondary'); await settled(N.page);
  const row = await N.page.evaluate(() => Array.from(document.querySelectorAll('#view-container tbody tr')).find(r => r.children[1].textContent.trim() === 'Asuncion').children[2].innerText.replace(/\s+/g, ' ').trim());
  ok(row === 'Sam Secondary Secondary Principal', 'Division Summary lists the coordinator of the level in view (Secondary)');
  ok(N.errors.length === 0, 'no page errors' + (N.errors[0] ? ': ' + N.errors[0] : ''));
  await N.ctx.close();

  for (const [user, name, pos] of [['asuncion_elemcoord', 'Elena Elementary', 'Elementary Supervisor'], ['asuncion_seccoord', 'Sam Secondary', 'Secondary Principal']]) {
    const C = await openNew(user, demo.slice(0, 40));
    await C.page.evaluate(() => { window.__STUB.districts[0].elem_coordinator_name = 'Elena Elementary'; window.__STUB.districts[0].elem_coordinator_position = 'Elementary Supervisor'; window.__STUB.districts[0].sec_coordinator_name = 'Sam Secondary'; window.__STUB.districts[0].sec_coordinator_position = 'Secondary Principal'; });
    await C.page.evaluate(() => initDB().then(() => { switchView('district-view'); })); await settled(C.page);
    ok(await C.page.evaluate(() => [document.getElementById('sig-p-name').textContent, document.getElementById('sig-p-pos').textContent].join('|')) === `${name}|Asuncion ${pos}`, `${user}: the printed "Prepared by" is their own level's coordinator`);
    const w = await C.page.evaluate(async () => (await sb().from('districts').update({ elem_coordinator_name: 'hacked' }).eq('id', 1).select('id')).data.length);
    ok(w === 0 && await C.page.evaluate(() => window.__STUB.districts[0].elem_coordinator_name === 'Elena Elementary'), `${user}: cannot change coordinator details through the API`);
    await C.ctx.close();
  }
}


console.log('\n[18] Chart colours, and editing least learned competencies');
{
  // ---- colours: distinct, consistent, readable; data unchanged (parity tests above already compare the values)
  const hexRgb = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255);
  const lin = c => c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  const lum = h => { const [r, g, b] = hexRgb(h).map(lin); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
  const lab = h => { const [r, g, b] = hexRgb(h).map(lin); const x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047, y = 0.2126 * r + 0.7152 * g + 0.0722 * b, z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883; const f = t => t > 0.008856 ? Math.cbrt(t) : 7.787 * t + 16 / 116; return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))]; };
  const dE = (a, b) => Math.hypot(...lab(a).map((v, i) => v - lab(b)[i]));
  const minDE = a => { let m = 999; for (let i = 0; i < a.length; i++) for (let j = i + 1; j < a.length; j++) m = Math.min(m, dE(a[i], a[j])); return m; };
  const N = await openNew('admin', demoNew);
  await N.page.evaluate(() => switchView('dashboard')); await settled(N.page);
  const cols = async () => N.page.evaluate(() => Object.fromEntries(Object.entries(activeCharts).map(([k, c]) => [k, { labels: c.data.labels, colors: c.data.datasets[0].backgroundColor, data: c.data.datasets[0].data }])));
  let c1 = await cols();
  ok(c1.distMps.labels.length === 11 && new Set(c1.distMps.colors).size === 11 && minDE(c1.distMps.colors) >= 20, 'district chart: 11 bars, 11 different colours, none too similar (min colour distance ' + minDE(c1.distMps.colors).toFixed(1) + ')');
  ok(new Set(c1.subMps.colors).size === 5 && minDE(c1.subMps.colors) >= 20, 'program track chart: 5 distinct colours');
  ok(new Set(c1.mapehComp.colors).size === 5 && minDE(c1.mapehComp.colors) >= 20, 'MAPEH components chart: 5 distinct colours');
  const allCols = [...c1.distMps.colors, ...c1.subMps.colors, ...c1.mapehComp.colors];
  ok(allCols.every(c => 1.05 / (lum(c) + 0.05) >= 3), 'every bar colour has at least 3:1 contrast against the white chart background');
  ok(JSON.stringify(c1.subMps.colors) === JSON.stringify(await N.page.evaluate(() => TRACK_COLORS)) && c1.distMps.colors[2] === (await N.page.evaluate(() => districtColor('Carmen'))), 'colours come from the one shared palette');
  // consistent under a filter: Carmen keeps its colour although other districts drop out
  await N.page.selectOption('#flt-keystage', 'Key Stage 3'); await settled(N.page);
  await N.page.evaluate(() => { window.__tmp = 1; });
  const c2 = await cols();
  ok(c2.distMps.labels.length === 11 && c2.distMps.colors[2] === c1.distMps.colors[2], 'a district keeps its colour under a filter');
  await N.page.evaluate(() => { resetFilters(); });
  await N.page.selectOption('#flt-district', 'Carmen'); await settled(N.page);
  const c3 = await cols();
  ok(JSON.stringify(c3.distMps.labels) === '["Carmen"]' && c3.distMps.colors[0] === c1.distMps.colors[2], 'a single-district view still uses that district\'s colour');
  // phone width stays readable
  await N.ctx.close();
  const M = await openNew('admin', demoNew, {}, { width: 360, height: 740 });
  await M.page.evaluate(() => switchView('dashboard')); await settled(M.page);
  ok(await M.page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth && Array.from(document.querySelectorAll('canvas')).every(c => c.getBoundingClientRect().width <= window.innerWidth)), 'charts fit a 360 px screen with no sideways scroll');
  await M.ctx.close();

  // ---- competency editing
  const ownIdx = demoNew.findIndex(r => r.district === 'Asuncion' && r.gradeLevel === 'Grade 4' && r.learningArea === 'SPA - Vocal Arts' && r.term === 'Term 1');
  const A = await openNew('asuncion_elemcoord', demoNew);
  const rid = ownIdx + 1;
  await A.page.evaluate(() => switchView('least-learned')); await settled(A.page);
  const nEdit = await A.page.locator('#view-container button:has-text("Edit")').count();
  const nLog = await A.page.evaluate(() => Number(document.querySelector('.badge-proficient + *, .card-box-header .badge').textContent.match(/\d+/) ? 0 : 0));
  ok(nEdit > 0 && nEdit === await A.page.evaluate(() => document.querySelectorAll('#view-container tbody tr td.screen-only').length), 'every logged competency row has an Edit button (coordinator, not only the Supervisor): ' + nEdit);
  const before = await A.page.evaluate(id => ({ count: window.__STUB.records.length, rec: JSON.parse(JSON.stringify(window.__STUB.records.find(r => r.id === id))) }), rid);
  const oldDesc = demoNew[ownIdx].leastLearned[1].desc, occ = t => t.split(oldDesc).length - 1; const occBefore = occ(await text(A.page));
  await A.page.evaluate(() => { const h = document.getElementById('qa-hide'); if (h) h.remove(); });
  await A.page.evaluate(([id, i]) => openCompetencyEditor(id, i), [rid, 1]);
  const form = await A.page.evaluate(() => [document.getElementById('comp-code').value, document.getElementById('comp-desc').value]);
  ok(form[0] === demoNew[ownIdx].leastLearned[1].code && form[1] === demoNew[ownIdx].leastLearned[1].desc, 'the form loads the existing entry');
  await A.page.fill('#comp-desc', '   '); await A.page.click('#comp-save');
  ok(/cannot be empty/.test(await A.page.textContent('#rec-error')), 'empty description is refused before saving');
  await A.page.fill('#comp-code', ''); await A.page.fill('#comp-desc', 'x'); await A.page.click('#comp-save');
  ok(/Enter a competency code/.test(await A.page.textContent('#rec-error')), 'empty code is refused');
  await A.page.fill('#comp-code', 'LC-2'); await A.page.fill('#comp-desc', 'Corrected competency text'); await A.page.click('#comp-save');
  await A.page.waitForSelector('.toast-success'); await settled(A.page);
  const after = await A.page.evaluate(id => ({ count: window.__STUB.records.length, rec: window.__STUB.records.find(r => r.id === id) }), rid);
  ok(after.count === before.count && after.rec.least_learned.length === before.rec.least_learned.length && after.rec.least_learned[1].desc === 'Corrected competency text' && after.rec.least_learned[1].code === 'LC-2'
    && after.rec.least_learned[0].desc === before.rec.least_learned[0].desc, 'the existing entry is updated in place: no new record, no duplicate entry, neighbours untouched');
  ok(['district_id', 'grade_level', 'learning_area', 'sy', 'term', 'school', 'education_level', 'mps'].every(k => after.rec[k] === before.rec[k]), 'district, level, program, grade, school year, term and scores are unchanged');
  { const t = await text(A.page); ok(/Corrected competency text/.test(t) && occ(t) === occBefore - 1, 'the Least Learned view shows the corrected text, and the old text appears exactly once less'); }
  // persists after a refresh (new page load reading the same data)
  await A.page.evaluate(() => { formDirty = false; return getAllRecords(); }).then(async rs => ok(rs.find(r => r.id === rid).leastLearned[1].desc === 'Corrected competency text', 'the change is read back from the database'));
  // stale edit and direct API attempts
  const api = await A.page.evaluate(async ([rid2, far, lvl]) => {
    const r = {};
    r.stale = (await sb().rpc('app_edit_competency', { p_id: rid2, p_index: 1, p_old_desc: 'old text', p_code: 'LC-2', p_desc: 'x' })).error?.message;
    r.far = (await sb().rpc('app_edit_competency', { p_id: far, p_index: 0, p_old_desc: window.__STUB.records.find(x => x.id === far).least_learned[0].desc, p_code: 'LC-1', p_desc: 'hijack' })).error?.message;
    r.lvl = (await sb().rpc('app_edit_competency', { p_id: lvl, p_index: 0, p_old_desc: window.__STUB.records.find(x => x.id === lvl).least_learned[0].desc, p_code: 'LC-1', p_desc: 'hijack' })).error?.message;
    r.farUnchanged = !JSON.stringify(window.__STUB.records.find(x => x.id === far).least_learned).includes('hijack') && !JSON.stringify(window.__STUB.records.find(x => x.id === lvl).least_learned).includes('hijack');
    return r;
  }, [rid, demoNew.findIndex(r => r.district === 'Carmen' && r.gradeLevel === 'Grade 4') + 1, demoNew.findIndex(r => r.district === 'Asuncion' && r.gradeLevel === 'Grade 8') + 1]);
  ok(/changed by someone else/.test(api.stale), 'a stale edit is refused');
  ok(/could not be found/.test(api.far) && /could not be found/.test(api.lvl) && api.farUnchanged, 'a coordinator cannot edit another district\'s or the other level\'s competencies, even by calling the database directly');
  // offline: readable error and no false success
  await A.page.evaluate(() => switchView('least-learned')); await settled(A.page);
  await A.page.evaluate(([id, i]) => openCompetencyEditor(id, i), [rid, 0]);
  await A.page.fill('#comp-desc', 'offline attempt'); await A.page.evaluate(() => { window.__STUB_OFFLINE = true; }); await A.page.click('#comp-save');
  await A.page.waitForFunction(() => document.getElementById('rec-error').textContent.length > 0);
  ok(/Could not reach the server/.test(await A.page.textContent('#rec-error')) && !(await A.page.evaluate(id => JSON.stringify(window.__STUB.records.find(r => r.id === id).least_learned).includes('offline attempt'), rid)), 'offline: a readable error, nothing saved, no success message');
  await A.ctx.close();
  for (const user of ['admin', 'supervisor']) {
    const D = await openNew(user, demoNew);
    const id = demoNew.findIndex(r => r.district === 'Carmen' && r.gradeLevel === 'Grade 8') + 1;
    await D.page.evaluate(() => switchView('least-learned')); await settled(D.page);
    await D.page.evaluate(([i]) => openCompetencyEditor(i, 0), [id]);
    await D.page.fill('#comp-desc', user + ' fix'); await D.page.click('#comp-save'); await D.page.waitForSelector('.toast-success');
    ok(await D.page.evaluate(i => window.__STUB.records.find(r => r.id === i).least_learned[0].desc, id) === user + ' fix', `${user} can edit competencies anywhere`);
    await D.ctx.close();
  }
}

console.log(`\n${pass} passed, ${fail} failed`);
await browser.close(); server.close();
process.exit(fail ? 1 : 0);
