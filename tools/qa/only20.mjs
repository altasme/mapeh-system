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

const ROOT = '/home/user/mapeh-system';
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
  pct75: r.pct75, proficiency_level: r.proficiencyLevel, least_learned: r.leastLearned, is_demo: r.isDemo !== false, school_id: r.schoolId ?? null, baseline_sy: r.baselineSy ?? null });

// ---------- browser plumbing ----------
const browser = await chromium.launch();
let legacyInfo = null; // passwords etc. read from the legacy file, kept in memory only
async function context(kind, viewport) {
  const ctx = await browser.newContext({ viewport: viewport || { width: 1280, height: 900 }, acceptDownloads: true });
  await ctx.route('**/*', async route => {
    const u = route.request().url();
    if (u.startsWith(BASE)) {
      const pathname = new URL(u).pathname;
      if (/^\/admin(\/|$)/.test(pathname) && !/\.(js|css)$/.test(pathname)) {   // the admin page answers /admin and every /admin/<screen> path
        const html = fs.readFileSync(path.join(ROOT, 'public/admin/index.html'), 'utf8').replace(/ integrity="[^"]+"/g, '');
        return route.fulfill({ contentType: 'text/html', body: html });
      }
      if (/^\/admin\/.+\.(js|css)$/.test(pathname)) return route.fulfill({ contentType: pathname.endsWith('.js') ? 'text/javascript' : 'text/css', body: fs.readFileSync(path.join(ROOT, 'public', pathname)) });
      if (pathname === '/content-registry.js') return route.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(path.join(ROOT, 'public/content-registry.js')) });
      if (pathname === '/config.js') return route.fulfill({ contentType: 'text/javascript', body:
        'window.APP_CONFIG={environment:"test",supabaseUrl:"https://qa.invalid",supabasePublishableKey:"qa-key",authEmailDomain:"users.mapehdavnor.altasme.app",features:{}};' });
      if (/\.(woff2)$/.test(pathname)) return route.fulfill({ status: 404, body: '' });
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
  const allPw = Object.assign({}, pw, Object.fromEntries(LEVEL_ACCOUNTS.map(a => [a.username, a.password])), extra.passwords || {});
  const profs = JSON.parse(JSON.stringify(profiles)).concat(JSON.parse(JSON.stringify(extra.profiles || []))).map(p => Object.assign(p, { must_change_password: p.must_change_password || (extra.mustChange || []).includes(p.username) }));
  pw = allPw;
  const stub = { districts: JSON.parse(JSON.stringify(districts)), profiles: profs, passwords: allPw, records: records.map((r, i) => Object.assign({ id: i + 1 }, toRowish(r))),
    notes: extra.notes || [], settings: JSON.parse(JSON.stringify(settingsSeed)),
    schools: JSON.parse(JSON.stringify(extra.schools || [])), school_programs: JSON.parse(JSON.stringify(extra.schoolPrograms || [])),
    site_content: JSON.parse(JSON.stringify(extra.siteContent || [])), site_settings: JSON.parse(JSON.stringify(extra.siteSettings || [])), site_media: JSON.parse(JSON.stringify(extra.siteMedia || [])), site_media_slots: JSON.parse(JSON.stringify(extra.siteSlots || [])) };
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
function canonPorted(t) { return t.toLowerCase().replace(/\s+/g, ' ').replace(/ ?sy not recorded/g, '').trim().replace(/no data no data/g, 'nd').replace(/no data/g, 'nd').replace(/tracked specializations \d+ \d+ mapeh,/g, 'tracked specializations N N mapeh,'); }
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
console.log('\n[20] Admin panel (/admin)');
{
  const SCH = [{ id: 1, name: 'Alpha IPED School', district_id: 1, active: true }, { id: 2, name: 'Beta SP School', district_id: 1, active: true }];
  const PRG = [{ school_id: 1, program: 'iped' }, { school_id: 2, program: 'special_programs' }];
  const base = { schools: SCH, schoolPrograms: PRG };
  const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
  async function openAdmin(extra = {}, viewport) {
    const ctx = await context('new', viewport); const page = await ctx.newPage(); const errors = []; page.on('pageerror', e => errors.push(String(e)));
    const { passwords: pw } = await readPasswords();
    const allPw = Object.assign({}, pw, Object.fromEntries(LEVEL_ACCOUNTS.map(a => [a.username, a.password])), extra.passwords || {});
    const stub = { districts: JSON.parse(JSON.stringify(districts)), profiles: JSON.parse(JSON.stringify(profiles)).concat(JSON.parse(JSON.stringify(extra.profiles || []))), passwords: allPw,
      records: (extra.records || demo.slice(0, 30)).map((r, i) => Object.assign({ id: i + 1 }, toRowish(r))), notes: [], settings: JSON.parse(JSON.stringify(settingsSeed)),
      schools: JSON.parse(JSON.stringify(SCH)), school_programs: JSON.parse(JSON.stringify(PRG)), site_content: [], site_settings: [], site_media: [], site_media_slots: [] };
    await page.addInitScript(s => { if (!window.__STUB) window.__STUB = s; }, stub);   // keep the same stand-in across /admin screens in one page load
    if (extra.clock) await ctx.clock.install({ time: new Date() });
    await page.goto(`${BASE}${extra.path || '/admin/'}`);
    return { ctx, page, errors, pw: allPw };
  }
  const ready = page => page.waitForFunction(() => { const p = document.getElementById('page'); return p && !/Loading\.\.\./.test(p.textContent) && p.textContent.length > 0; }, null, { timeout: 15000 });
  async function login(A, user, pass) { await A.page.fill('#lu', user); await A.page.fill('#lp', pass); await A.page.click('#login-btn'); }
  async function asAdmin(extra, viewport) { const A = await openAdmin(extra, viewport); await A.page.waitForSelector('#login-form'); await login(A, 'admin', A.pw.admin); await A.page.waitForSelector('#page'); await ready(A.page); return A; }
  const go = async (A, p2) => { await A.page.click(`.side nav a[href="${p2}"]`); await ready(A.page); };
  const stubOf = (A, k) => A.page.evaluate(k2 => JSON.parse(JSON.stringify(window.__STUB[k2])), k);

  // ---- access and authentication
  {
    const A = await openAdmin({ path: '/admin/users' }); await A.page.waitForSelector('#login-form');
    ok(await A.page.locator('.side').count() === 0 && /Administrator sign in/.test(await A.page.textContent('#app')), 'an unauthenticated visit to /admin/users shows only the sign-in form');
    await login(A, 'admin', 'definitely-wrong'); await A.page.waitForFunction(() => document.getElementById('login-error').textContent.length > 0);
    ok(/Invalid username or password/.test(await A.page.textContent('#login-error')) && await A.page.locator('.side').count() === 0, 'a wrong password is rejected');
    for (let i = 0; i < 4; i++) { await login(A, 'admin', 'wrong' + i); await A.page.waitForTimeout(80); }
    await login(A, 'admin', A.pw.admin); await A.page.waitForTimeout(150);
    ok(/Too many attempts/.test(await A.page.textContent('#login-error')) && await A.page.locator('.side').count() === 0, 'after repeated failures the form pauses further attempts (the server also rate-limits)');
    await A.ctx.close();
    for (const user of ['supervisor', 'asuncion_elemcoord']) {
      const B = await openAdmin(); await B.page.waitForSelector('#login-form'); await login(B, user, B.pw[user]);
      await B.page.waitForFunction(() => /not authorized/i.test(document.getElementById('login-error').textContent));
      ok(await B.page.locator('.side').count() === 0 && await B.page.evaluate(() => !sessionStorage.getItem('stub_session')), `${user}: signing in to /admin is refused, no admin screen, session closed`);
      ok(await B.page.evaluate(() => window.__STUB.admin_activity.some(a => a.action === 'admin.access_denied' && a.outcome === 'denied')), `${user}: the attempt is recorded in the audit log`);
      await B.ctx.close();
    }
  }

  // ---- admin session, dashboard, navigation
  const A = await asAdmin();
  ok(new URL(A.page.url()).pathname === '/admin/dashboard', 'after sign-in the administrator lands on /admin/dashboard');
  const stats = await A.page.evaluate(() => Array.from(document.querySelectorAll('.stat')).map(x => [x.querySelector('span').textContent, x.querySelector('strong').textContent]));
  const profs = await stubOf(A, 'profiles');
  ok(stats[0][1] === String(profs.length) && stats[1][1] === String(profs.filter(p => p.active !== false).length) && stats[2][1] === String(profs.filter(p => p.active === false).length), 'dashboard counts match the real profiles (total, active, disabled)');
  ok(stats.find(x => x[0] === 'Active schools')[1] === '2' && stats.find(x => x[0] === 'School Account accounts' || x[0] === 'School Account')[1] !== undefined, 'school and role counts come from the data');
  ok(/admin\.login/.test(await A.page.textContent('#page')), 'the sign-in is in the recent activity');
  const navs = await A.page.evaluate(() => Array.from(document.querySelectorAll('.side nav a')).map(a => a.textContent));
  ok(JSON.stringify(navs) === JSON.stringify(['Dashboard', 'User Management', 'Roles and Permissions', 'Website Content', 'Image and Media Library', 'Website Settings', 'Audit Logs', 'Account Settings']), 'navigation lists every admin module, with Logout below');
  await go(A, '/admin/roles');
  ok(new URL(A.page.url()).pathname === '/admin/roles' && /Administrator[\s\S]*Supervisor[\s\S]*District Coordinator[\s\S]*School Account/.test(await A.page.textContent('#page')) && /not editable|deliberately not editable/.test(await A.page.textContent('#page')), 'Roles and Permissions shows the role matrix (view only)');
  ok(await A.page.evaluate(() => !document.querySelector('#page input[type=checkbox]')), 'the matrix has no toggles');

  // ---- user management
  await go(A, '/admin/users');
  ok((await A.page.locator('#u-table tbody tr').count()) === Math.min(25, profs.length) && /Showing 1 to \d+ of \d+/.test(await A.page.textContent('#u-pager')), 'user directory is listed with a paged total');
  await A.page.fill('#u-search', 'dujali'); await A.page.waitForFunction(() => /of 2\b/.test(document.getElementById('u-pager').textContent), null, { timeout: 6000 }).catch(async () => console.log('PAGER:', await A.page.textContent('#u-pager')));
  ok((await A.page.locator('#u-table tbody tr').count()) === 2 && !/[$]2[ab]\$/.test(await A.page.textContent('#u-table')), 'search narrows the list');
  await A.page.fill('#u-search', ''); await A.page.selectOption('#u-role', 'supervisor'); await A.page.waitForFunction(() => document.querySelectorAll('#u-table tbody tr').length === 1);
  ok(!/encrypted|hash|token/i.test(await A.page.textContent('#u-table')), 'the directory shows no password hashes or tokens');
  await A.page.selectOption('#u-role', '');
  await A.page.click('#u-new'); await A.page.waitForSelector('#uf');
  await A.page.fill('#f-user', 'ab'); await A.page.fill('#f-name', 'X'); await A.page.fill('#f-pass', 'longenough1'); await A.page.click('#uf-save');
  ok(/Username must be/.test(await A.page.textContent('#uf-error')), 'create: invalid username refused');
  await A.page.fill('#f-user', 'new.coord'); await A.page.selectOption('#f-role', 'district_coordinator'); await A.page.click('#uf-save');
  ok(/needs a district and an education level/.test(await A.page.textContent('#uf-error')), 'create: a coordinator needs a district and level');
  ok(await A.page.locator('#g-school').isHidden(), 'the form adapts to the role (school field hidden for coordinators)');
  await A.page.selectOption('#f-district', { label: 'Carmen' }); await A.page.selectOption('#f-level', 'secondary'); await A.page.fill('#f-pass', 'short'); await A.page.click('#uf-save');
  ok(/8 to 72/.test(await A.page.textContent('#uf-error')), 'create: short password refused');
  await A.page.click('#f-gen'); const gen = await A.page.inputValue('#f-pass'); ok(gen.length === 14, 'a strong password can be generated');
  await A.page.click('#uf-save'); await A.page.waitForSelector('.toast.ok');
  let nu = (await stubOf(A, 'profiles')).find(p => p.username === 'new.coord');
  ok(nu && nu.role === 'district_coordinator' && nu.district_id === 3 && nu.education_level === 'secondary' && nu.active, 'the user is created in the real profile table with the right assignments');
  await A.page.click('#u-new'); await A.page.waitForSelector('#uf'); await A.page.fill('#f-user', 'new.coord'); await A.page.fill('#f-name', 'Dup'); await A.page.selectOption('#f-role', 'supervisor'); await A.page.fill('#f-pass', 'longenough1'); await A.page.click('#uf-save');
  await A.page.waitForFunction(() => document.getElementById('uf-error').textContent.length > 0);
  ok(/already taken/.test(await A.page.textContent('#uf-error')), 'create: a duplicate username is refused by the server');
  await A.page.selectOption('#f-role', 'school'); await A.page.fill('#f-user', 'alpha.acct'); await A.page.selectOption('#f-school', { index: 1 }); await A.page.click('#uf-save'); await A.page.waitForSelector('.toast.ok');
  nu = (await stubOf(A, 'profiles')).find(p => p.username === 'alpha.acct');
  ok(nu && nu.role === 'school' && nu.school_id === 1 && nu.district_id === 1, 'a school account is created for the chosen school, in its district');
  await A.page.click('#u-new'); await A.page.waitForSelector('#uf'); await A.page.fill('#f-user', 'alpha.again'); await A.page.fill('#f-name', 'Again'); await A.page.selectOption('#f-role', 'school'); await A.page.selectOption('#f-school', { index: 1 }); await A.page.fill('#f-pass', 'longenough1'); await A.page.click('#uf-save');
  await A.page.waitForFunction(() => document.getElementById('uf-error').textContent.length > 0);
  ok(/already has an active account/.test(await A.page.textContent('#uf-error')), 'a school cannot get two active accounts');
  await A.page.click('#uf-cancel');
  // edit: role and assignment
  await A.page.fill('#u-search', 'new.coord'); await A.page.waitForFunction(() => document.querySelectorAll('#u-table tbody tr').length === 1);
  await A.page.click('[data-edit]'); await A.page.waitForSelector('#uf'); await A.page.fill('#f-name', 'Renamed Coordinator'); await A.page.selectOption('#f-district', { label: 'Langilan' }); await A.page.click('#uf-save'); await A.page.waitForSelector('.toast.ok');
  nu = (await stubOf(A, 'profiles')).find(p => p.username === 'new.coord');
  ok(nu.display_name === 'Renamed Coordinator' && nu.district_id === 11 && nu.education_level === 'secondary', 'edits persist (name and district)');
  await A.page.click('[data-edit]'); await A.page.waitForSelector('#uf'); await A.page.selectOption('#f-role', 'supervisor'); await A.page.click('#uf-save'); await A.page.waitForSelector('.toast.ok');
  nu = (await stubOf(A, 'profiles')).find(p => p.username === 'new.coord');
  ok(nu.role === 'supervisor' && nu.district_id == null && nu.education_level == null, 'a role change persists and clears assignments that no longer apply');
  // disable / enable, password reset
  A.page.on('dialog', d => d.accept());
  await A.page.click('[data-toggle]'); await A.page.waitForSelector('.toast.ok');
  ok((await stubOf(A, 'profiles')).find(p => p.username === 'new.coord').active === false, 'disable works');
  await A.page.click('[data-toggle]'); await A.page.waitForSelector('.toast.ok');
  await A.page.click('[data-pw]'); await A.page.waitForSelector('#pf'); await A.page.fill('#p-new', 'short'); await A.page.click('#pf-save');
  ok(/8 to 72/.test(await A.page.textContent('#pf-error')), 'reset: short password refused');
  await A.page.fill('#p-new', 'ResetPass-7788'); await A.page.click('#pf-save'); await A.page.waitForSelector('#pf-done .badge');
  ok((await stubOf(A, 'passwords'))['new.coord'] === 'ResetPass-7788' && !/ResetPass/.test(JSON.stringify(await stubOf(A, 'admin_activity'))), 'the new password is set and is not written to the activity log');
  ok(!/\bpassword\b[^.]*(is|was)\s+[A-Za-z0-9]{8}/i.test(await A.page.textContent('#pf')), 'no stored password is ever displayed');
  await A.page.click('#pf-cancel');
  // last administrator and self-disable
  await A.page.fill('#u-search', 'admin'); await A.page.waitForFunction(() => document.querySelectorAll('#u-table tbody tr').length >= 1);
  const adminRow = A.page.locator('#u-table tbody tr', { hasText: 'System Administrator' });
  await adminRow.locator('[data-toggle]').click(); await A.page.waitForSelector('.toast.err');
  ok(/last active administrator|cannot disable your own/.test(await A.page.textContent('#toast-host')), 'the last administrator cannot be disabled');
  await adminRow.locator('[data-edit]').click(); await A.page.waitForSelector('#uf'); await A.page.selectOption('#f-role', 'supervisor'); await A.page.click('#uf-save');
  await A.page.waitForFunction(() => document.getElementById('uf-error').textContent.length > 0);
  ok(/last active administrator/.test(await A.page.textContent('#uf-error')) && (await stubOf(A, 'profiles')).find(p => p.username === 'admin').role === 'admin', 'nor demoted');
  await A.page.click('#uf-cancel');
  ok(await A.page.evaluate(() => window.__STUB.records.length) === 30, 'user changes never touch assessment records');

  // ---- website content
  await go(A, '/admin/content');
  const item = k => A.page.locator(`.item[data-key="${k}"]`);
  ok(await A.page.locator('.item').count() === 8 && await A.page.locator('.tab').count() >= 4, 'content is grouped by page (Login page, Screen headings, ...)');
  await item('login.title').locator('textarea').fill('Division of Davao del Norte Assessment');
  await item('login.title').locator('[data-do=preview]').click();
  ok(/Division of Davao del Norte Assessment/.test(await item('login.title').locator('.preview').textContent()), 'preview shows the new text');
  let dialogMsg = ''; A.page.removeAllListeners('dialog'); A.page.once('dialog', d => { dialogMsg = d.message(); d.dismiss(); });
  await A.page.click('.side nav a[href="/admin/users"]');
  ok(/unsaved changes/i.test(dialogMsg) && new URL(A.page.url()).pathname === '/admin/content', 'leaving with unsaved edits asks for confirmation and can be cancelled');
  A.page.on('dialog', d => d.accept());
  await item('login.title').locator('[data-do=cancel]').click();
  ok(await item('login.title').locator('textarea').inputValue() === 'Division Assessment Consolidation System', 'Cancel restores the saved text');
  await item('login.title').locator('textarea').fill('Bad <b>html</b>'); await item('login.title').locator('[data-do=save]').click();
  ok(/Plain text only/.test(await item('login.title').locator('.error').textContent()), 'HTML is refused');
  await item('login.title').locator('textarea').fill('   '); await item('login.title').locator('[data-do=save]').click();
  ok(/cannot be empty/.test(await item('login.title').locator('.error').textContent()), 'empty text is refused');
  await item('login.title').locator('textarea').fill('Davao del Norte Assessment System'); await item('login.title').locator('[data-do=save]').click(); await A.page.waitForSelector('.toast.ok'); await ready(A.page);
  ok((await stubOf(A, 'site_content')).some(c => c.key === 'login.title' && c.value === 'Davao del Norte Assessment System') && /Edited/.test(await item('login.title').textContent()), 'saved to the database and marked Edited');
  await item('login.title').locator('textarea').fill('Second wording'); await item('login.title').locator('[data-do=save]').click(); await A.page.waitForSelector('.toast.ok'); await ready(A.page);
  await item('login.title').locator('[data-do=history]').click(); await A.page.waitForSelector('[data-restore]');
  ok(await A.page.locator('[data-restore]').count() === 2, 'history lists each change');
  await A.page.locator('[data-restore]').first().click(); await A.page.waitForSelector('.toast.ok'); await ready(A.page);
  ok((await stubOf(A, 'site_content')).find(c => c.key === 'login.title').value === 'Davao del Norte Assessment System', 'an earlier version can be restored');
  await item('login.desc').locator('textarea').fill('Line one\nLine two'); await item('login.desc').locator('[data-do=save]').click(); await A.page.waitForSelector('.toast.ok'); await ready(A.page);
  ok((await stubOf(A, 'site_content')).find(c => c.key === 'login.desc').value === 'Line one\nLine two', 'line breaks are preserved');
  await item('login.desc').locator('[data-do=reset]').click(); await A.page.waitForSelector('.toast.ok'); await ready(A.page);
  ok(!(await stubOf(A, 'site_content')).some(c => c.key === 'login.desc'), 'Reset to default removes the override');
  await A.page.click('.tab:has-text("Screen headings")'); await item('view.dashboard').locator('textarea').fill('Results Dashboard'); await item('view.dashboard').locator('[data-do=save]').click(); await A.page.waitForSelector('.toast.ok');

  // ---- images
  await go(A, '/admin/media');
  ok(await A.page.locator('.slots .tile').count() === 5, 'five image positions are listed (brand logo and the printed report logos)');
  await A.page.click('#m-upload'); await A.page.waitForSelector('#mf');
  await A.page.setInputFiles('#m-file', { name: 'notes.txt', mimeType: 'text/plain', buffer: Buffer.from('hello') });
  ok(/Only PNG, JPEG or WebP/.test(await A.page.textContent('#mf-error')), 'a non-image is rejected');
  await A.page.setInputFiles('#m-file', { name: 'big.png', mimeType: 'image/png', buffer: Buffer.alloc(2 * 1024 * 1024 + 10) });
  ok(/2 MB or smaller/.test(await A.page.textContent('#mf-error')), 'an oversized image is rejected');
  await A.page.setInputFiles('#m-file', { name: 'logo.png', mimeType: 'image/png', buffer: PNG });
  await A.page.waitForSelector('#m-prev img'); ok(true, 'a valid image previews before saving');
  await A.page.fill('#m-alt', 'Division logo'); await A.page.selectOption('#m-slot', 'brand.logo'); await A.page.click('#mf-save'); await A.page.waitForSelector('.toast.ok'); await ready(A.page);
  const media = await stubOf(A, 'site_media'), slots = await stubOf(A, 'site_media_slots'), store = await stubOf(A, 'storage');
  ok(media.length === 1 && media[0].alt_text === 'Division logo' && slots[0].slot === 'brand.logo' && slots[0].media_id === media[0].id && Object.keys(store).includes(media[0].path), 'the file is stored, registered with its description, and assigned to the position');
  ok(await A.page.locator('[data-del]').isDisabled(), 'an image in use cannot be deleted');
  await A.page.click('#m-upload'); await A.page.waitForSelector('#mf'); await A.page.setInputFiles('#m-file', { name: 'banner.jpg', mimeType: 'image/jpeg', buffer: PNG }); await A.page.click('#mf-save'); await A.page.waitForSelector('.toast.ok'); await ready(A.page);
  await A.page.locator('.slots .tile', { hasText: 'Brand logo' }).locator('[data-replace]').click(); await A.page.waitForSelector('#m-existing');
  await A.page.selectOption('#m-existing', { index: 1 }); await A.page.click('#mf-save'); await A.page.waitForSelector('.toast.ok'); await ready(A.page);
  const slots2 = await stubOf(A, 'site_media_slots'); ok(slots2.length === 1 && slots2[0].media_id !== slots[0].media_id, 'a position can be switched to another library image');
  await A.page.locator('.library .tile', { hasText: 'logo.png' }).locator('[data-del]').click(); await A.page.waitForSelector('.toast', { state: 'attached' }); await ready(A.page);
  ok((await stubOf(A, 'site_media')).length === 1 && !Object.keys(await stubOf(A, 'storage')).includes(media[0].path), 'once no longer used, an image can be deleted (record and file)');
  const prevMedia = await stubOf(A, 'site_media'), prevSlots = await stubOf(A, 'site_media_slots');

  // ---- settings
  await go(A, '/admin/settings');
  await A.page.fill('#s-title', 'Davao del Norte Division Assessment'); await A.page.fill('#s-org', 'SDO Davao del Norte (Test)'); await A.page.locator('form[data-setting=titles] button').click(); await A.page.waitForSelector('.toast.ok');
  await A.page.check('#a-on'); await A.page.selectOption('#a-level', 'warning'); await A.page.fill('#a-text', ''); await A.page.locator('form[data-setting=announcement] button').click();
  await A.page.waitForFunction(() => /Enter the announcement text/.test(document.querySelector('form[data-setting=announcement] .error').textContent));
  ok(true, 'an announcement cannot be turned on without a message');
  await A.page.fill('#a-text', 'Scheduled maintenance on Friday'); await A.page.locator('form[data-setting=announcement] button').click(); await A.page.waitForSelector('.toast.ok');
  await A.page.fill('#s-title', '<b>x</b>'); await A.page.locator('form[data-setting=titles] button').click(); await A.page.waitForFunction(() => /Plain text only/.test(document.querySelector('form[data-setting=titles] .error').textContent));
  ok(true, 'unsafe characters in settings are refused by the server');
  await A.page.fill('#s-title', 'Davao del Norte Division Assessment');
  await A.page.selectOption('#d-view', 'dashboard'); await A.page.selectOption('#d-sy', '2025-2026'); await A.page.locator('form[data-setting=landing] button').click(); await A.page.waitForSelector('.toast.ok');
  await A.page.fill('#c-email', 'not-an-email'); await A.page.locator('form[data-setting=contact] button').click(); await A.page.waitForFunction(() => /valid email/.test(document.querySelector('form[data-setting=contact] .error').textContent));
  await A.page.fill('#c-email', 'sdo@example.org'); await A.page.fill('#c-phone', '(084) 555 0100'); await A.page.fill('#c-addr', 'Tagum City'); await A.page.locator('form[data-setting=contact] button').click(); await A.page.waitForSelector('.toast.ok');
  const sets = await stubOf(A, 'site_settings'); ok(['site.title', 'org.name', 'announcement', 'default_view', 'default_sy', 'contact'].every(k => sets.some(x => x.key === k)), 'all supported settings are saved');
  const savedContent = await stubOf(A, 'site_content');

  // ---- audit log
  await go(A, '/admin/audit');
  const auditText = await A.page.textContent('#page');
  ok(['admin.login', 'user.create', 'user.update', 'user.password_reset', 'content.update', 'content.restore', 'content.reset', 'media.upload', 'media.assign', 'media.delete', 'settings.update'].every(x => auditText.includes(x)), 'every kind of administrative action appears in the audit log');
  ok(!/ResetPass|longenough1|initialpass/.test(auditText + JSON.stringify(await stubOf(A, 'admin_activity'))), 'the audit log holds no passwords');
  await A.page.selectOption('#a-action', 'content.'); await A.page.waitForFunction(() => !/user\.create/.test(document.getElementById('page').textContent));
  ok(/content\.update/.test(await A.page.textContent('#page')), 'the log can be filtered by action');
  await A.page.click('.tab:has-text("Data changes")'); await ready(A.page); ok(/Data changes|recorded automatically/.test(await A.page.textContent('#page')), 'the data-change log is available');

  // ---- own account: optional password change, logout
  await go(A, '/admin/account');
  await A.page.fill('#cp-old', 'wrong-current-1'); await A.page.fill('#cp-new', 'Calm-Harbor-2026'); await A.page.fill('#cp-conf', 'Calm-Harbor-2026'); await A.page.click('#cp-save');
  await A.page.waitForFunction(() => document.getElementById('cp-error').textContent.length > 0);
  ok(/current password is incorrect/.test(await A.page.textContent('#cp-error')), 'a wrong current password is refused');
  await A.page.fill('#cp-old', A.pw.admin); await A.page.fill('#cp-new', 'short1'); await A.page.fill('#cp-conf', 'short1'); await A.page.click('#cp-save');
  ok(/at least 10 characters/.test(await A.page.textContent('#cp-error')), 'a weak new password is refused');
  await A.page.fill('#cp-new', 'Calm-Harbor-2026'); await A.page.fill('#cp-conf', 'Calm-Harbor-2027'); await A.page.click('#cp-save');
  ok(/do not match/.test(await A.page.textContent('#cp-error')), 'mismatched confirmation refused');
  await A.page.fill('#cp-conf', 'Calm-Harbor-2026'); await A.page.click('#cp-save'); await A.page.waitForSelector('.toast.ok');
  ok((await stubOf(A, 'passwords')).admin === 'Calm-Harbor-2026' && (await stubOf(A, 'admin_activity')).some(a => a.action === 'admin.password_changed_self'), 'the administrator can change their own password (optional) and it is logged');
  await A.page.click('[data-act=logout]'); await A.page.waitForSelector('#login-form');
  ok(await A.page.evaluate(() => !sessionStorage.getItem('stub_session')) && (await stubOf(A, 'admin_activity')).some(a => a.action === 'admin.logout'), 'logout ends the session and is logged');
  await A.page.evaluate(() => history.pushState({}, '', '/admin/users')); await A.page.reload(); await A.page.waitForSelector('#login-form');
  ok(await A.page.locator('.side').count() === 0, 'after logout, protected screens ask for sign-in again');
  ok(A.errors.length === 0, 'no uncaught page errors in the admin panel' + (A.errors[0] ? ': ' + A.errors[0] : ''));
  await A.ctx.close();

  // ---- the saved content is what the website shows (fresh page, same data)
  {
    const N = await openNew('admin', demo.slice(0, 30), Object.assign({}, base, { noLogin: true, siteContent: savedContent, siteSettings: sets, siteMedia: prevMedia, siteSlots: prevSlots }));
    const login = await N.page.evaluate(() => ({ title: document.querySelector('[data-cms="login.title"]').textContent, doc: document.title, org: document.querySelector('[data-cms-org]').textContent, ann: document.getElementById('login-announcement').textContent, annHidden: document.getElementById('login-announcement').hidden,
      contact: document.getElementById('login-contact').textContent, logo: document.getElementById('brand-logo-login').getAttribute('src') || '', logoShown: document.getElementById('brand-logo-login').style.display, desc: document.querySelector('[data-cms="login.desc"]').textContent }));
    ok(login.title === 'Davao del Norte Assessment System' && login.doc === 'Davao del Norte Division Assessment' && login.org === 'SDO Davao del Norte (Test)', 'the sign-in page shows the edited title, browser-tab title and organization name');
    ok(!login.annHidden && /Scheduled maintenance/.test(login.ann) && /sdo@example.org/.test(login.contact) && /Tagum City/.test(login.contact), 'the announcement and contact details appear on the sign-in page');
    ok(/storage\/v1\/object\/public\/site-media\//.test(login.logo) && login.logoShown === 'block', 'the brand logo from the media library appears');
    ok(/consolidated by district/.test(login.desc), 'text that was reset to default shows the original wording');
    await N.page.fill('#login-username', 'admin'); await N.page.fill('#login-password', (await readPasswords()).passwords.admin); await N.page.click('#login-screen button[type=submit]');
    await N.page.waitForFunction(() => document.getElementById('login-screen').style.display === 'none'); await settled(N.page);
    const app = await N.page.evaluate(() => ({ view: currentView, title: document.getElementById('view-title').textContent, sy: document.getElementById('flt-sy').value, ann: document.getElementById('site-announcement').textContent, annHidden: document.getElementById('site-announcement').hidden, annClass: document.getElementById('site-announcement').className }));
    ok(app.view === 'dashboard' && app.title === 'Results Dashboard' && app.sy === '2025-2026', 'after sign-in: the chosen landing screen, the edited screen heading and the default school year');
    ok(!app.annHidden && /Scheduled maintenance/.test(app.ann) && /level-warning/.test(app.annClass), 'the announcement banner shows on every screen with its style');
    ok(N.errors.length === 0, 'the website runs without errors with edited content' + (N.errors[0] ? ': ' + N.errors[0] : ''));
    await N.ctx.close();
  }

  // ---- idle timeout and a signed-in non-admin opening /admin
  {
    const I = await asAdmin({ clock: true });
    await I.page.clock.fastForward('31:00'); await I.page.waitForSelector('#login-form', { timeout: 10000 });
    ok(/30 minutes of inactivity/.test(await I.page.textContent('#login-error')) && await I.page.evaluate(() => !sessionStorage.getItem('stub_session')), 'an idle administrator is signed out after 30 minutes');
    await I.ctx.close();
    const X = await openAdmin(); await X.page.waitForSelector('#login-form');
    await X.page.evaluate(async ([e, p]) => { sessionStorage.setItem('stub_session', JSON.stringify({ user: { id: window.__STUB.profiles.find(x => x.username === 'supervisor').id, email: e } })); }, ['supervisor@users.mapehdavnor.altasme.app']);
    await X.page.reload(); await X.page.waitForFunction(() => /Not authorized/.test(document.getElementById('app').textContent));
    ok(await X.page.locator('.side').count() === 0 && await X.page.evaluate(() => window.__STUB.admin_activity.some(a => a.action === 'admin.access_denied')), 'a signed-in Supervisor who opens /admin sees "Not authorized" and no administrative screen');
    const rpcs = await X.page.evaluate(async () => { const c = window.supabase.createClient('https://qa.invalid', 'k'); const out = {}; for (const [n, a] of [['app_admin_create_user', { p_username: 'sneaky', p_display_name: 'x', p_role: 'admin', p_district_id: null, p_education_level: null, p_school_id: null, p_password: 'longenough1' }], ['app_admin_save_content', { p_key: 'login.title', p_value: 'hacked' }], ['app_admin_set_password', { p_id: 'x', p_password: 'longenough1' }], ['app_admin_update_user', { p_id: 'x', p_username: 'abc', p_display_name: 'x', p_role: 'admin', p_district_id: null, p_education_level: null, p_school_id: null, p_active: true }]]) out[n] = (await c.rpc(n, a)).error?.code; return out; });
    ok(Object.values(rpcs).every(c => c === '42501') && !(await stubOf(X, 'profiles')).some(p => p.username === 'sneaky') && (await stubOf(X, 'site_content')).length === 0, 'a Supervisor calling the admin functions directly is refused and nothing changes');
    await X.ctx.close();
  }

  // ---- phones
  {
    const M = await asAdmin({}, { width: 360, height: 740 });
    ok(await M.page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), 'the admin dashboard has no sideways scroll at 360 px');
    ok(!(await M.page.locator('.side').isVisible().catch(() => false)) || await M.page.evaluate(() => document.getElementById('side').getBoundingClientRect().right <= 0), 'the menu is tucked away on a phone');
    await M.page.click('[data-act=menu]'); await M.page.waitForTimeout(250);
    ok(await M.page.evaluate(() => document.getElementById('side').getBoundingClientRect().left >= 0), 'the menu button opens it');
    await M.page.click('.side nav a[href="/admin/users"]'); await ready(M.page);
    ok(await M.page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'the user list fits a phone (the table scrolls inside its card)');
    await M.ctx.close();
  }
}

console.log(`\n${pass} passed, ${fail} failed`);
await browser.close(); server.close();
process.exit(fail ? 1 : 0);
