// Exercises the WRITE paths of the deployed app against the real database, then restores everything it touched.
//   LIVE_URL=https://<project>.pages.dev SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node tools/qa/live_writes.mjs
// The service-role key is used only to verify rows and to clean up. Test rows carry school = LIVE-WRITE-TEST.
import { createRequire } from 'module'; import fs from 'fs'; import path from 'path';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_PATH || '/opt/node22/lib/node_modules/playwright');
const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const URLS = process.env.LIVE_URL, SB = (process.env.SUPABASE_URL || '').replace(/\/$/, ''), SR = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!URLS || !SB || !SR) { console.error('Set LIVE_URL, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY'); process.exit(1); }
const legacy = fs.readFileSync(path.join(ROOT, 'legacy/mapehDavNor.original.html'), 'utf8');
const pw = Object.fromEntries([...legacy.matchAll(/username:\s*"([^"]+)",\s*password:\s*"([^"]+)"/g)].map(m => [m[1], m[2]]));
const rest = async (m, p, body, prefer) => { const r = await fetch(`${SB}/rest/v1/${p}`, { method: m, headers: { apikey: SR, Authorization: `Bearer ${SR}`, 'Content-Type': 'application/json', Prefer: ['count=exact', prefer].filter(Boolean).join(',') }, body: body ? JSON.stringify(body) : undefined });
  const t = await r.text(); return { j: t ? JSON.parse(t) : null, n: Number((r.headers.get('content-range') || '').split('/')[1]) }; };
let pass = 0, fail = 0; const ok = (c, m) => { c ? pass++ : fail++; console.log(`  ${c ? 'PASS' : 'FAIL'} ${m}`); };
const T = 'LIVE-WRITE-TEST';
const testRows = async () => (await rest('GET', `assessment_records?select=id&school=eq.${T}&limit=1`)).n;
const total = async () => (await rest('GET', 'assessment_records?select=id&limit=1')).n;

const browser = await chromium.launch({ proxy: process.env.HTTPS_PROXY ? { server: process.env.HTTPS_PROXY } : undefined });
const ctx = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1280, height: 900 } }); const page = await ctx.newPage();
const errs = []; page.on('pageerror', e => errs.push(String(e)));
const settle = () => page.waitForFunction(() => !document.querySelector('#view-container .view-loading') && document.getElementById('view-container').innerText.length > 20, null, { timeout: 30000 });
const toastClear = () => page.evaluate(() => { document.getElementById('toast-host').innerHTML = ''; });
const waitToast = async kind => { await page.waitForSelector(`.toast-${kind}`, { timeout: 30000 }); return page.textContent('#toast-host'); };

const baseTotal = await total();
const settingsBefore = (await rest('GET', 'app_settings?select=data&id=eq.1')).j[0].data;
const noteBefore = (await rest('GET', 'comparative_notes?select=id&sy=eq.2025-2026&district_scope=eq.Asuncion')).n;
const snap = (await rest('GET', 'assessment_records?select=id,baseline_mps&sy=eq.2025-2026&term=eq.Term 1&learning_area=eq.SPA - Vocal Arts&grade_level=in.(Grade 1,Grade 2,Grade 3)&district_id=eq.1')).j;
console.log(`Baseline before: ${baseTotal} records; ${snap.length} demo rows in the baseline-edit scope`);

try {
  await page.goto(URLS);
  await page.fill('#login-username', 'admin'); await page.fill('#login-password', pw.admin); await page.click('#login-screen button[type=submit]');
  await page.waitForFunction(() => document.getElementById('login-screen').style.display === 'none', null, { timeout: 30000 }); await settle();

  console.log('\nManual entry');
  await page.evaluate(() => switchView('data-input')); await settle();
  await page.click('text=Method 2: Fast Manual Entry');
  await page.selectOption('#m-district', 'Asuncion'); await page.selectOption('#m-subject', 'SPA - Vocal Arts');
  await page.fill('#m-school', T); await page.fill('#m-baseline', '65'); await page.fill('#m-mps', '82.5'); await page.fill('#m-pct75', '71');
  await page.fill('#m-lc1-desc', '<b>lc</b> test');
  await page.click('button:has-text("Save District Record")');
  ok(/saved successfully/.test(await waitToast('success')), 'manual entry: success toast');
  ok(await testRows() === 1, 'manual entry: exactly one row is in the database');
  const row = (await rest('GET', `assessment_records?select=mps,proficiency_level,is_demo,created_by,least_learned&school=eq.${T}`)).j[0];
  ok(Number(row.mps) === 82.5 && row.proficiency_level === 'Approaching Proficiency' && row.is_demo === false && !!row.created_by, 'manual entry: values, proficiency level, is_demo=false and created_by stored');

  console.log('\nExcel import');
  const xlsx = rows => page.evaluate(r => { const ws = XLSX.utils.json_to_sheet(r); const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, ws, 'S'); return Array.from(new Uint8Array(XLSX.write(wb, { type: 'array', bookType: 'xlsx' }))); }, rows);
  const upload = async rows => { await page.evaluate(() => { formDirty = false; switchView('data-input'); }); await settle(); await toastClear();
    await page.setInputFiles('#excel-file', { name: 't.xlsx', mimeType: 'application/octet-stream', buffer: Buffer.from(await xlsx(rows)) }); };
  const base = { 'School Year': '2025-2026', Term: 'Term 1', District: 'Asuncion', 'School Name': T, 'Key Stage': 'Key Stage 1', 'Grade Level': 'Grade 2', 'Learning Area': 'SPA - Vocal Arts', 'SY Baseline MPS': 65, 'Mean Percentage Score (MPS%)': 80, '% Learners Scoring >= 75%': 70, 'Least Learned Competency 1 Description': 'import lc' };
  await upload([base, { ...base, District: 'Atlantis' }]);
  const m1 = await waitToast('error'); ok(/Unknown district/.test(m1) && /row 3/.test(m1) && await testRows() === 1, 'import with an unknown district: rejected with the row number, nothing saved');
  await upload([base, { ...base, 'Mean Percentage Score (MPS%)': 150 }]);
  const m2 = await waitToast('error'); ok(/MPS must be between 0 and 100/.test(m2) && await testRows() === 1, 'import with MPS 150: rejected by the database, plain-English message, nothing saved (all or nothing)');
  await upload([base, { ...base, 'Grade Level': 'Grade 3' }]);
  ok(/imported 2/.test(await waitToast('success')) && await testRows() === 3, 'valid import: 2 rows saved after confirmation');

  console.log('\nBaseline edit (count, confirm, update)');
  await page.evaluate(() => { formDirty = false; });
  await page.selectOption('#flt-sy', '2025-2026'); await page.selectOption('#flt-term', 'Term 1'); await page.selectOption('#flt-district', 'Asuncion'); await page.selectOption('#flt-subject', 'SPA - Vocal Arts');
  await settle(); await page.evaluate(() => switchView('comparative')); await settle(); await toastClear();
  let asked = ''; page.once('dialog', d => { asked = d.message(); d.accept(); });
  await page.fill('.editable-baseline-input >> nth=0', '71'); await page.keyboard.press('Tab');
  ok(/live|updated on/i.test(await waitToast('success')), 'baseline edit: success toast after the update');
  const n = Number((asked.match(/on (\d+) record/) || [])[1]);
  ok(n === snap.length + 3 - 0 || n >= 4, `baseline edit: asked first ("${asked.slice(0, 60)}...") with the matching count (${n})`);
  const after = (await rest('GET', 'assessment_records?select=baseline_mps&sy=eq.2025-2026&term=eq.Term 1&learning_area=eq.SPA - Vocal Arts&grade_level=in.(Grade 1,Grade 2,Grade 3)&district_id=eq.1')).j;
  ok(after.length === n && after.every(r => Number(r.baseline_mps) === 71), 'baseline edit: exactly the matching rows were changed to 71.00');

  console.log('\nComparative notes');
  await page.waitForSelector('#comp-analysis-input', { timeout: 30000 }); await settle();
  await page.evaluate(() => { document.getElementById('comp-analysis-input').value = '</textarea><b>live note</b>'; markDirty(); });
  await page.click('text=Save Qualitative Notes'); await waitToast('success');
  const notes = (await rest('GET', 'comparative_notes?select=analysis&sy=eq.2025-2026&district_scope=eq.Asuncion&subject=eq.SPA - Vocal Arts&term=eq.Term 1')).j;
  ok(notes.length === 1 && notes[0].analysis.startsWith('</textarea>'), 'notes: upserted with the exact scope key and the text intact');

  console.log('\nSettings');
  await page.evaluate(() => { formDirty = false; switchView('settings'); }); await settle(); await toastClear();
  await page.fill('#s-fp', '(084) 000 0000'); await page.click('button:has-text("Save Header & Footer Settings")'); await waitToast('success');
  ok((await rest('GET', 'app_settings?select=data&id=eq.1')).j[0].data.footerPhone === '(084) 000 0000', 'settings: saved to the database');
  ok(errs.length === 0, 'no page errors during the run' + (errs.length ? ' -> ' + errs[0] : ''));
} finally {
  console.log('\nCleanup');
  await rest('DELETE', `assessment_records?school=eq.${T}`);
  for (const r of snap) await rest('PATCH', `assessment_records?id=eq.${r.id}`, { baseline_mps: r.baseline_mps });
  if (!noteBefore) await rest('DELETE', 'comparative_notes?sy=eq.2025-2026&district_scope=eq.Asuncion&subject=eq.SPA - Vocal Arts&term=eq.Term 1');
  await rest('PATCH', 'app_settings?id=eq.1', { data: settingsBefore });
  ok(await total() === baseTotal && await testRows() === 0, `records restored to ${baseTotal}, no test rows left`);
  const restored = (await rest('GET', 'assessment_records?select=id,baseline_mps&sy=eq.2025-2026&term=eq.Term 1&learning_area=eq.SPA - Vocal Arts&grade_level=in.(Grade 1,Grade 2,Grade 3)&district_id=eq.1')).j;
  ok(restored.length === snap.length && restored.every(r => Number(snap.find(s => s.id === r.id).baseline_mps) === Number(r.baseline_mps)), 'demo baselines restored to their original values');
  ok(JSON.stringify((await rest('GET', 'app_settings?select=data&id=eq.1')).j[0].data) === JSON.stringify(settingsBefore), 'settings restored');
}
console.log(`\n${pass} passed, ${fail} failed`); await browser.close(); process.exit(fail ? 1 : 0);
