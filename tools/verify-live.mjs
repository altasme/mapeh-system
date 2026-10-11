#!/usr/bin/env node
// Live check of the Appendix C access rules against the REAL Supabase project, over its public API,
// signed in as real accounts. Passwords are read from legacy/ at run time and never printed.
//   SUPABASE_URL=... SUPABASE_PUBLISHABLE_KEY=... SUPABASE_SERVICE_ROLE_KEY=... node tools/verify-live.mjs
// The service-role key is used only to clean up the few rows this script creates.
import fs from 'fs';
import path from 'path';
const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const U = (process.env.SUPABASE_URL || '').replace(/\/$/, ''), PUB = process.env.SUPABASE_PUBLISHABLE_KEY, SR = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!U || !PUB || !SR) { console.error('Set SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, SUPABASE_SERVICE_ROLE_KEY'); process.exit(1); }
const legacy = fs.readFileSync(path.join(ROOT, 'legacy/mapehDavNor.original.html'), 'utf8');
const pw = Object.fromEntries([...legacy.matchAll(/username:\s*"([^"]+)",\s*password:\s*"([^"]+)"/g)].map(m => [m[1], m[2]]));
const DOMAIN = 'users.mapehdavnor.altasme.app';
let pass = 0, fail = 0;
const ok = (c, m) => { c ? pass++ : fail++; console.log(`  ${c ? 'PASS' : 'FAIL'} ${m}`); };

async function login(u) {
  const r = await fetch(`${U}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: PUB, 'Content-Type': 'application/json' }, body: JSON.stringify({ email: `${u}@${DOMAIN}`, password: pw[u] }) });
  const j = await r.json(); if (!j.access_token) throw new Error(`login failed for ${u}: HTTP ${r.status}`); return j.access_token;
}
const api = (tok, key = PUB) => async (method, p, body, prefer) => {
  const r = await fetch(U + '/rest/v1/' + p, { method, headers: { apikey: key, Authorization: `Bearer ${tok || key}`, 'Content-Type': 'application/json', Prefer: ['count=exact', prefer].filter(Boolean).join(',') }, body: body ? JSON.stringify(body) : undefined });
  const t = await r.text(); let j = null; try { j = t ? JSON.parse(t) : null; } catch (_) {}
  return { s: r.status, j, n: Number((r.headers.get('content-range') || '').split('/')[1]), code: j && j.code };
};
const svc = api(SR, SR);
const denied = r => r.s === 401 || r.s === 403 || r.code === '42501';

const dist = Object.fromEntries((await svc('GET', 'districts?select=id,name')).j.map(d => [d.name, d.id]));
const A = api(await login('admin')), S = api(await login('supervisor')), C = api(await login('asuncion_coord')), K = api(await login('carmen_coord'));
const anon = api(null);
const rec = d => ({ sy: '2025-2026', term: 'Term 1', district_id: d, key_stage: 'Key Stage 1', grade_level: 'Grade 1', learning_area: 'LIVE-CHECK', baseline_mps: 65, mps: 80, pct75: 70, proficiency_level: 'Approaching Proficiency', is_demo: true });

console.log('\nRead');
ok((await A('GET', 'assessment_records?select=id&limit=1')).n === 1452, 'admin reads all 1,452 records');
ok((await S('GET', 'assessment_records?select=id&limit=1')).n === 1452, 'supervisor reads all 1,452 records');
const c1 = await C('GET', 'assessment_records?select=id&limit=1');
ok(c1.n === 132, `coordinator (Asuncion) reads only own district: ${c1.n} rows`);
ok((await C('GET', `assessment_records?select=id&district_id=eq.${dist['Carmen']}&limit=1`)).n === 0, 'coordinator sees 0 rows of another district');
ok(denied(await anon('GET', 'assessment_records?select=id&limit=1')), 'signed out: records denied');
ok(denied(await anon('GET', 'profiles?select=id&limit=1')), 'signed out: profiles denied');

console.log('\nInsert / update / delete');
const own = await C('POST', 'assessment_records?select=id', rec(dist['Asuncion']), 'return=representation');
ok(own.s === 201, 'coordinator inserts into own district');
const ownId = own.j && own.j[0] && own.j[0].id;
ok(denied(await C('POST', 'assessment_records', rec(dist['Carmen']))), 'coordinator cannot insert into another district');
const mv = await C('PATCH', `assessment_records?id=eq.${ownId}`, { district_id: dist['Carmen'] }, 'return=representation');
ok(denied(mv) || (Array.isArray(mv.j) && mv.j.length === 0), 'coordinator cannot move a record to another district');
const dl = await C('DELETE', `assessment_records?id=eq.${ownId}`, null, 'return=representation');
ok(denied(dl) || (Array.isArray(dl.j) && dl.j.length === 0), 'coordinator cannot delete');
const sp = await C('POST', 'assessment_records?select=created_by', Object.assign(rec(dist['Asuncion']), { created_by: '00000000-0000-0000-0000-000000000000' }), 'return=representation');
ok(sp.s >= 400 || (sp.j && sp.j[0] && sp.j[0].created_by !== '00000000-0000-0000-0000-000000000000'), 'created_by cannot be spoofed');
const mv2 = await A('POST', 'assessment_records?select=id', rec(dist['Carmen']), 'return=representation');
const mv2id = mv2.j && mv2.j[0] && mv2.j[0].id;
const adm = await A('PATCH', `assessment_records?id=eq.${mv2id}`, { district_id: dist['Asuncion'] }, 'return=representation');
ok(adm.s === 200 && adm.j.length === 1, 'admin moves a record between districts');
const sup = await S('DELETE', `assessment_records?id=eq.${mv2id}`, null, 'return=representation');
ok(sup.s === 200 && sup.j.length === 1, 'supervisor deletes a record');
const bad = await A('POST', 'assessment_records', Object.assign(rec(dist['Carmen']), { mps: 150 }));
ok(bad.code === '23514', 'database rejects MPS 150 (check constraint)');

console.log('\nNotes, settings, districts, profiles, audit');
const note = n => ({ sy: 'LIVECHECK', district_scope: n, subject: 'ALL', term: 'ALL', analysis: 'x', interventions: 'y' });
ok((await C('POST', 'comparative_notes', note('Asuncion'))).s === 201, 'coordinator writes a note for own district');
ok(denied(await C('POST', 'comparative_notes', note('Carmen'))), 'coordinator cannot write a note for another district');
ok((await K('GET', 'comparative_notes?select=id&sy=eq.LIVECHECK')).n === 0, 'other coordinator cannot read that note');
const setC = await C('PATCH', 'app_settings?id=eq.1', { updated_by: null }, 'return=representation');
ok(denied(setC) || (Array.isArray(setC.j) && setC.j.length === 0), 'coordinator cannot update settings');
const dC = await C('PATCH', `districts?id=eq.${dist['Asuncion']}`, { coordinator_name: 'x' }, 'return=representation');
ok(denied(dC) || (Array.isArray(dC.j) && dC.j.length === 0), 'coordinator cannot update districts');
const dA = await A('PATCH', `districts?id=eq.${dist['Asuncion']}`, { sort_order: 1 }, 'return=representation');
ok(dA.s === 200 && dA.j.length === 1, 'admin can update districts');
ok((await C('GET', 'app_settings?select=id')).n === 1, 'every user can read settings (needed for printing)');
ok((await C('GET', 'profiles?select=id')).n === 1 && (await A('GET', 'profiles?select=id')).n === 1, 'each user sees only their own profile');
const role = await C('PATCH', 'profiles?username=eq.asuncion_coord', { role: 'admin' }, 'return=representation');
ok(denied(role) || (Array.isArray(role.j) && role.j.length === 0), 'coordinator cannot change own role');
ok((await A('GET', 'audit_log?select=id&limit=1')).n > 0, 'admin reads the audit log');
for (const [n, f] of [['supervisor', S], ['coordinator', C]]) { const r = await f('GET', 'audit_log?select=id&limit=1'); ok(denied(r) || r.n === 0, `${n} cannot read the audit log`); }

// cleanup of rows this script made
await svc('DELETE', 'comparative_notes?sy=eq.LIVECHECK');
await svc('DELETE', 'assessment_records?learning_area=eq.LIVE-CHECK');
const left = await svc('GET', 'assessment_records?select=id&learning_area=eq.LIVE-CHECK&limit=1');
ok(left.n === 0, 'test rows cleaned up');
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
