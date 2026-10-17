#!/usr/bin/env node
// Provisions the 22 Elementary and Secondary coordinator accounts (11 districts x 2 levels) and retires the original
// 11 district-wide coordinator accounts. Run it AFTER supabase/migrations/0004_education_levels.sql.
//
//   SUPABASE_URL=https://<ref>.supabase.co SUPABASE_SERVICE_ROLE_KEY=<service key> node tools/provision-level-coordinators.mjs
//   add --dry-run to list what would happen without calling Supabase; add --no-retire to leave the old accounts active.
//
// Username:         {district_code}_elemcoord   and   {district_code}_seccoord
// Initial password: {district_code}@elem        and   {district_code}@sec     (built at run time, never printed or stored)
//
// Client decision (testing phase): no forced password change, so profiles are created with must_change_password = false (migration 0008). Formerly: until the user set a new password the database
// refuses them all data, and the app forces the change at first login. Idempotent: an account that already exists
// keeps its password and its flag; only its district, level and active state are brought back in line.
// The district codes are the ones already used by the original usernames (username without "_coord").
import fs from 'fs';

const CODES = {
  'Asuncion': 'asuncion', 'B.E. Dujali': 'dujali', 'Carmen': 'carmen', 'Kapalong East': 'kapalonge', 'Kapalong West': 'kapalongw',
  'New Corella': 'newcorella', 'San Isidro': 'sanisidro', 'Sto. Tomas East': 'stotomase', 'Sto. Tomas West': 'stotomasw',
  'Talaingod': 'talaingod', 'Langilan': 'langilan'
};
const LEVELS = [
  { level: 'elementary', label: 'Elementary', userTag: 'elemcoord', pwTag: 'elem' },
  { level: 'secondary', label: 'Secondary', userTag: 'seccoord', pwTag: 'sec' }
];
const DOMAIN = process.env.AUTH_EMAIL_DOMAIN || 'users.mapehdavnor.altasme.app';
const dry = process.argv.includes('--dry-run');
const retire = !process.argv.includes('--no-retire');
const URL_ = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

const plan = [];
for (const [district, code] of Object.entries(CODES)) for (const L of LEVELS)
  plan.push({ district, level: L.level, username: `${code}_${L.userTag}`, password: `${code}@${L.pwTag}`, name: `${district} ${L.label} Coordinator` });

if (dry) {
  console.log(`Dry run: would provision ${plan.length} accounts (initial passwords are not shown)`);
  plan.forEach(a => console.log(`  ${a.username}@${DOMAIN}  ${a.level}  ${a.district}`));
  console.log(retire ? 'Would retire the original district-wide coordinators (active = false, sign-in banned).' : 'Would leave the original coordinators untouched.');
  process.exit(0);
}
if (!URL_ || !KEY) { console.error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the environment.'); process.exit(1); }

const H = { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' };
async function call(method, p, body, extra = {}) {
  const r = await fetch(URL_ + p, { method, headers: { ...H, ...extra }, body: body ? JSON.stringify(body) : undefined });
  const text = await r.text(); let json = null; try { json = text ? JSON.parse(text) : null; } catch (_) { /* not json */ }
  return { status: r.status, json };
}
const must = (r, what) => { if (r.status >= 300) { console.error(`FAILED ${what}: HTTP ${r.status} ${JSON.stringify(r.json).slice(0, 160)}`); process.exit(1); } return r; };

const d = must(await call('GET', '/rest/v1/districts?select=id,name'), 'read districts');
const districtId = Object.fromEntries(d.json.map(x => [x.name, x.id]));
const probe = await call('GET', '/rest/v1/profiles?select=education_level,active,must_change_password&limit=1');
if (probe.status !== 200) { console.error('profiles.education_level is missing: run supabase/migrations/0004_education_levels.sql first.'); process.exit(1); }

let allUsers = [];
for (let page = 1; ; page++) { // every auth user (200 per page)
  const r = must(await call('GET', `/auth/v1/admin/users?page=${page}&per_page=200`), 'list users');
  allUsers = allUsers.concat(r.json.users || []);
  if ((r.json.users || []).length < 200) break;
}
let created = 0, kept = 0;
for (const a of plan) {
  if (!districtId[a.district]) { console.error(`Unknown district ${a.district}`); process.exit(1); }
  const email = `${a.username}@${DOMAIN}`;
  let id = (allUsers.find(u => u.email === email) || {}).id;
  if (!id) {
    const c = must(await call('POST', '/auth/v1/admin/users', { email, password: a.password, email_confirm: true }), `create ${a.username}`);
    id = c.json.id; created++;
    must(await call('POST', '/rest/v1/profiles', { id, username: a.username, display_name: a.name, role: 'district_coordinator',
      district_id: districtId[a.district], education_level: a.level, active: true, must_change_password: false }, { Prefer: 'return=minimal' }), `profile ${a.username}`);
  } else {
    kept++; // existing account: keep its password and its must-change flag
    const ex = await call('GET', `/rest/v1/profiles?select=id&id=eq.${id}`);
    const body = { district_id: districtId[a.district], education_level: a.level, active: true, role: 'district_coordinator', display_name: a.name, username: a.username };
    if (ex.json && ex.json.length) must(await call('PATCH', `/rest/v1/profiles?id=eq.${id}`, body, { Prefer: 'return=minimal' }), `update ${a.username}`);
    else must(await call('POST', '/rest/v1/profiles', { id, ...body, must_change_password: false }, { Prefer: 'return=minimal' }), `profile ${a.username}`);
  }
  console.log(`ok  ${a.username}`);
}

let retired = 0;
if (retire) {
  const newNames = new Set(plan.map(a => a.username));
  const old = must(await call('GET', '/rest/v1/profiles?select=id,username&role=eq.district_coordinator&education_level=is.null'), 'find original coordinators').json
    .filter(p => !newNames.has(p.username));
  for (const p of old) {
    must(await call('PATCH', `/rest/v1/profiles?id=eq.${p.id}`, { active: false }, { Prefer: 'return=minimal' }), `retire ${p.username}`);
    must(await call('PUT', `/auth/v1/admin/users/${p.id}`, { ban_duration: '876000h' }), `ban ${p.username}`); // reversible in the dashboard
    retired++; console.log(`retired ${p.username}`);
  }
}
console.log(`Done. ${created} created, ${kept} already existed (password and flag unchanged), ${retired} original coordinator(s) retired. Passwords were not printed.`);
