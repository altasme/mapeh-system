#!/usr/bin/env node
// Tests the access rules of ALL 22 level coordinators (plus Admin, Supervisor and the retired accounts) against the
// real project, signed in as each one over the public API, before anyone is told to use them.
//
//   SUPABASE_URL=... SUPABASE_PUBLISHABLE_KEY=... SUPABASE_SERVICE_ROLE_KEY=... node tools/verify-live-levels.mjs
//
// Initial passwords are rebuilt from the convention at run time; Admin and Supervisor passwords come from legacy/.
// Nothing is printed that contains a password. The script:
//   1. checks the initial-password gate (an account that must change its password can read and write nothing),
//   2. temporarily lifts the gate on each account with the service key, runs the district + level checks, and
//      puts the gate back (a test account never ends up unlocked by this script),
//   3. inserts and removes its own marker rows (school = LEVEL-TEST).
import fs from 'fs'; import path from 'path';
const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const U = (process.env.SUPABASE_URL || '').replace(/\/$/, ''), PUB = process.env.SUPABASE_PUBLISHABLE_KEY, SR = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!U || !PUB || !SR) { console.error('Set SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY and SUPABASE_SERVICE_ROLE_KEY'); process.exit(1); }
const DOMAIN = 'users.mapehdavnor.altasme.app';
const CODES = { 'Asuncion': 'asuncion', 'B.E. Dujali': 'dujali', 'Carmen': 'carmen', 'Kapalong East': 'kapalonge', 'Kapalong West': 'kapalongw', 'New Corella': 'newcorella', 'San Isidro': 'sanisidro', 'Sto. Tomas East': 'stotomase', 'Sto. Tomas West': 'stotomasw', 'Talaingod': 'talaingod', 'Langilan': 'langilan' };
const legacy = fs.readFileSync(path.join(ROOT, 'legacy/mapehDavNor.original.html'), 'utf8');
const oldPw = Object.fromEntries([...legacy.matchAll(/username:\s*"([^"]+)",\s*password:\s*"([^"]+)"/g)].map(m => [m[1], m[2]]));
let pass = 0, fail = 0; const ok = (c, m) => { c ? pass++ : fail++; if (!c || process.env.VERBOSE) console.log(`  ${c ? 'PASS' : 'FAIL'} ${m}`); };

const rest = (tok, key) => async (method, p, body, prefer) => {
  const r = await fetch(`${U}/rest/v1/${p}`, { method, headers: { apikey: key, Authorization: `Bearer ${tok || key}`, 'Content-Type': 'application/json', Prefer: ['count=exact', prefer].filter(Boolean).join(',') }, body: body ? JSON.stringify(body) : undefined });
  const t = await r.text(); let j = null; try { j = t ? JSON.parse(t) : null; } catch (_) {}
  return { s: r.status, j, n: Number((r.headers.get('content-range') || '').split('/')[1]), code: j && j.code };
};
const svc = rest(SR, SR);
const denied = r => r.s === 401 || r.s === 403 || r.code === '42501';
async function login(username, password) {
  const r = await fetch(`${U}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: PUB, 'Content-Type': 'application/json' }, body: JSON.stringify({ email: `${username}@${DOMAIN}`, password }) });
  const j = await r.json(); return j.access_token || null;
}

const dist = Object.fromEntries((await svc('GET', 'districts?select=id,name')).j.map(d => [d.name, d.id]));
const GRADE = { elementary: 'Grade 3', secondary: 'Grade 9' }, KS = { elementary: 'Key Stage 1', secondary: 'Key Stage 3' };
const rec = (d, level, tag) => ({ sy: '2025-2026', term: 'Term 1', district_id: d, school: 'LEVEL-TEST', key_stage: KS[level], grade_level: GRADE[level], learning_area: tag || 'LEVEL-TEST', baseline_mps: 65, mps: 80, pct75: 70, proficiency_level: 'Approaching Proficiency', is_demo: true });
const other = l => (l === 'elementary' ? 'secondary' : 'elementary');

// marker rows: one per district and level, so every account has something to find and something to be kept away from
const seed = []; for (const [name, id] of Object.entries(dist)) for (const l of ['elementary', 'secondary']) seed.push(rec(id, l));
const admin = (await svc('GET', 'profiles?select=id&username=eq.admin')).j[0].id;
await svc('DELETE', 'assessment_records?school=eq.LEVEL-TEST');
ok((await svc('POST', 'assessment_records', seed.map(r => ({ ...r, created_by: admin })), 'return=minimal')).s < 300, `seeded ${seed.length} marker rows`);

const flagState = {};
try {
  for (const [district, code] of Object.entries(CODES)) for (const level of ['elementary', 'secondary']) {
    const username = `${code}_${level === 'elementary' ? 'elemcoord' : 'seccoord'}`;
    const tag = `${username}`;
    const prof = (await svc('GET', `profiles?select=id,must_change_password,active,education_level,district_id&username=eq.${username}`)).j[0];
    if (!prof) { ok(false, `${tag}: profile exists`); continue; }
    flagState[prof.id] = prof.must_change_password;
    ok(prof.education_level === level && prof.district_id === dist[district] && prof.active, `${tag}: profile is ${level} / ${district} / active`);
    const tok = await login(username, `${code}@${level === 'elementary' ? 'elem' : 'sec'}`);
    if (!tok) { // already changed its password: cannot test with the initial one, so test through a service-issued session is impossible
      console.log(`  SKIP ${tag}: initial password no longer works (already changed); only the SQL matrix covers it`); continue; }
    const A = rest(tok, PUB);

    // 1. the gate: while the flag is set, no data at all
    await svc('PATCH', `profiles?id=eq.${prof.id}`, { must_change_password: true }, 'return=minimal');
    const g1 = await A('GET', 'assessment_records?select=id&limit=1');
    ok(g1.n === 0 || denied(g1), `${tag}: initial password sees no records`);
    ok(denied(await A('POST', 'assessment_records', rec(dist[district], level))), `${tag}: initial password cannot write`);
    const own = await A('GET', 'profiles?select=must_change_password');
    ok(own.j && own.j.length === 1 && own.j[0].must_change_password === true, `${tag}: can still read its own profile to learn it must change the password`);

    // 2. lift the gate for the test and check scope
    await svc('PATCH', `profiles?id=eq.${prof.id}`, { must_change_password: false }, 'return=minimal');
    const mine = await A('GET', 'assessment_records?select=id,district_id,education_level&school=eq.LEVEL-TEST');
    ok(mine.j && mine.j.length === 1 && mine.j[0].district_id === dist[district] && mine.j[0].education_level === level, `${tag}: sees exactly its own district and level (${mine.j ? mine.j.length : 'error'} marker row)`);
    const everything = await A('GET', 'assessment_records?select=id,district_id,education_level&limit=2000');
    ok(everything.j.every(r => r.district_id === dist[district] && r.education_level === level), `${tag}: no row of any other district or level is readable`);
    const makeOwn = await A('POST', 'assessment_records?select=id', rec(dist[district], level, tag), 'return=representation');
    ok(makeOwn.s === 201, `${tag}: can create in own district and level`);
    ok(denied(await A('POST', 'assessment_records', rec(dist[district], other(level)))), `${tag}: cannot create the other level in the same district`);
    const otherDist = Object.values(dist).find(i => i !== dist[district]);
    ok(denied(await A('POST', 'assessment_records', rec(otherDist, level))), `${tag}: cannot create in another district`);
    const id = makeOwn.j && makeOwn.j[0] && makeOwn.j[0].id;
    const mv = await A('PATCH', `assessment_records?id=eq.${id}`, { grade_level: GRADE[other(level)] }, 'return=representation');
    ok(denied(mv) || (Array.isArray(mv.j) && mv.j.length === 0), `${tag}: cannot move its record to the other level`);
    const del = await A('DELETE', `assessment_records?id=eq.${id}`, null, 'return=representation');
    ok(denied(del) || (Array.isArray(del.j) && del.j.length === 0), `${tag}: cannot hard delete`);
    // migration 0005: soft delete through scope-checked functions, protected columns, MAPEH grade rule
    const otherRow = (await svc('GET', `assessment_records?select=id&school=eq.LEVEL-TEST&district_id=eq.${dist[district]}&education_level=eq.${other(level)}`)).j[0];
    ok(otherRow && denied(await A('POST', 'rpc/app_delete_records', { p_ids: [otherRow.id] })), `${tag}: cannot soft delete the other level (function refuses)`);
    ok(denied(await A('PATCH', `assessment_records?id=eq.${id}`, { is_demo: true })) && denied(await A('PATCH', `assessment_records?id=eq.${id}`, { deleted_at: '2020-01-01' })), `${tag}: cannot set is_demo or deleted_at through the API`);
    ok(denied(await A('POST', 'rpc/app_delete_records_by_sy', { p_sy: '2025-2026' })) && denied(await A('POST', 'rpc/app_restore_records', { p_ids: [id] })), `${tag}: cannot bulk delete or restore`);
    const mapehBad = await A('POST', 'assessment_records', { ...rec(dist[district], level), grade_level: 'Grade 3', learning_area: 'MAPEH - Music' });
    ok(mapehBad.s === 400 && mapehBad.code === '23514', `${tag}: the database refuses Music for Grade 3`);
    const softOwn = await A('POST', 'rpc/app_delete_records', { p_ids: [id], p_reason: 'verify' });
    ok(softOwn.s === 200 && softOwn.j === 1, `${tag}: can soft delete its own record`);
    ok(((await A('GET', `assessment_records?select=id&id=eq.${id}`)).j || []).length === 0, `${tag}: a deleted record disappears for the coordinator`);
    const bad = await A('POST', 'assessment_records', { ...rec(dist[district], level), grade_level: 'Grade 13' });
    ok(bad.s >= 400, `${tag}: an unknown grade level is refused`);
    const note = l => ({ sy: 'LEVELTEST', district_scope: district, education_level: l, subject: 'ALL', term: 'ALL', analysis: 'x', interventions: 'y' });
    ok((await A('POST', 'comparative_notes', note(level))).s === 201, `${tag}: can write a note for its own level`);
    ok(denied(await A('POST', 'comparative_notes', note(other(level)))), `${tag}: cannot write a note for the other level`);
    ok(denied(await A('POST', 'comparative_notes', note('all'))), `${tag}: cannot write a division-wide note`);
    const roleChange = await A('PATCH', `profiles?id=eq.${prof.id}`, { education_level: other(level), active: true, must_change_password: false }, 'return=representation');
    ok(denied(roleChange) || (Array.isArray(roleChange.j) && roleChange.j.length === 0), `${tag}: cannot edit its own level or security flags`);

    // 3. put the gate back
    await svc('PATCH', `profiles?id=eq.${prof.id}`, { must_change_password: flagState[prof.id] }, 'return=minimal');
  }

  // Admin and Supervisor see both levels everywhere; the original coordinators are retired
  for (const u of ['admin', 'supervisor']) {
    const tok = await login(u, oldPw[u]); const A = rest(tok, PUB);
    const r = await A('GET', 'assessment_records?select=id,education_level&school=eq.LEVEL-TEST&limit=1000');
    ok(r.j && r.j.length === seed.length && new Set(r.j.map(x => x.education_level)).size === 2, `${u}: sees all ${seed.length} marker rows across both levels`);
  }
  for (const [u, p] of Object.entries(oldPw)) if (/_coord$/.test(u)) {
    const tok = await login(u, p);
    if (!tok) { ok(true, `${u}: sign-in refused (retired)`); continue; }
    const r = await rest(tok, PUB)('GET', 'assessment_records?select=id&limit=1');
    ok(r.n === 0 || denied(r), `${u}: retired, sees no records`);
  }
} finally {
  await svc('DELETE', 'assessment_records?school=eq.LEVEL-TEST');
  await svc('DELETE', 'assessment_records?learning_area=like.*_coord');
  await svc('DELETE', 'comparative_notes?sy=eq.LEVELTEST');
  for (const [id, flag] of Object.entries(flagState)) await svc('PATCH', `profiles?id=eq.${id}`, { must_change_password: flag }, 'return=minimal');
  ok((await svc('GET', 'assessment_records?select=id&school=eq.LEVEL-TEST&limit=1')).n === 0, 'marker rows removed, gates restored');
}
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
