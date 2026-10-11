#!/usr/bin/env node
// Creates the 13 accounts of CLAUDE.md Appendix D in Supabase Auth and inserts their profiles rows.
// Passwords are read from legacy/mapehDavNor.original.html at run time (spec 8.4). They are never printed,
// logged or written anywhere. The service-role key comes from the environment and is never printed either.
//
//   SUPABASE_URL=https://<ref>.supabase.co SUPABASE_SERVICE_ROLE_KEY=... node tools/provision-accounts.mjs
//   add --dry-run to list what would be created without calling Supabase
//
// Idempotent: an existing auth user is kept (its password is NOT changed) and its profile is upserted.
import fs from 'fs';
import path from 'path';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const DOMAIN = process.env.AUTH_EMAIL_DOMAIN || 'users.mapehdavnor.altasme.app';
const dry = process.argv.includes('--dry-run');
const URL_ = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

const html = fs.readFileSync(path.join(ROOT, 'legacy/mapehDavNor.original.html'), 'utf8');
const block = html.match(/const USER_ACCOUNTS = \[([\s\S]*?)\n\];/);
if (!block) { console.error('USER_ACCOUNTS not found in legacy file'); process.exit(1); }
const accounts = [...block[1].matchAll(/\{\s*username:\s*"([^"]+)",\s*password:\s*"([^"]+)",\s*name:\s*"([^"]+)",\s*role:\s*"([^"]+)",\s*district:\s*"([^"]+)"\s*\}/g)]
  .map(m => ({ username: m[1], password: m[2], name: m[3], role: { 'Admin': 'admin', 'Supervisor': 'supervisor', 'District Coordinator': 'district_coordinator' }[m[4]], district: m[5] === 'ALL' ? null : m[5] }));
if (accounts.length !== 13 || accounts.some(a => !a.role)) { console.error(`Expected 13 valid accounts, found ${accounts.length}`); process.exit(1); }

if (dry) {
  console.log('Dry run: would provision', accounts.length, 'accounts');
  accounts.forEach(a => console.log(`  ${a.username}@${DOMAIN}  ${a.role}  ${a.district || '(division)'}`));
  process.exit(0);
}
if (!URL_ || !KEY) { console.error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the environment.'); process.exit(1); }

const H = { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' };
async function call(method, p, body, extra = {}) {
  const r = await fetch(URL_ + p, { method, headers: { ...H, ...extra }, body: body ? JSON.stringify(body) : undefined });
  const text = await r.text();
  let json = null; try { json = text ? JSON.parse(text) : null; } catch (_) { /* not json */ }
  return { status: r.status, json };
}

const d = await call('GET', '/rest/v1/districts?select=id,name');
if (d.status !== 200 || !d.json.length) { console.error('Could not read districts. Run supabase/seed/districts.sql first.'); process.exit(1); }
const districtId = Object.fromEntries(d.json.map(x => [x.name, x.id]));

let created = 0, kept = 0;
for (const a of accounts) {
  const email = `${a.username}@${DOMAIN}`;
  let id = null;
  const c = await call('POST', '/auth/v1/admin/users', { email, password: a.password, email_confirm: true });
  if (c.status === 200 || c.status === 201) { id = c.json.id; created++; }
  else {
    // already exists: find it
    const l = await call('GET', '/auth/v1/admin/users?per_page=200');
    const u = l.json && (l.json.users || []).find(x => x.email === email);
    if (!u) { console.error(`FAILED ${a.username}: HTTP ${c.status}`); process.exit(1); }
    id = u.id; kept++;
  }
  if (a.district && !districtId[a.district]) { console.error(`FAILED ${a.username}: unknown district ${a.district}`); process.exit(1); }
  const p = await call('POST', '/rest/v1/profiles?on_conflict=id',
    { id, username: a.username, display_name: a.name, role: a.role, district_id: a.district ? districtId[a.district] : null },
    { Prefer: 'resolution=merge-duplicates,return=minimal' });
  if (p.status >= 300) { console.error(`FAILED profile ${a.username}: HTTP ${p.status}`); process.exit(1); }
  console.log(`ok  ${a.username}`);
}
console.log(`Done. ${created} created, ${kept} already existed (password unchanged). Passwords were not printed.`);
