#!/usr/bin/env node
// Administrative password reset. The user must choose a new password again at next login.
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... NEW_PASSWORD='temporary-secret' node tools/reset-password.mjs <username>
// The temporary password comes from the environment (never from a file or argument) and is never printed.
const username = process.argv[2];
const URL_ = (process.env.SUPABASE_URL || '').replace(/\/$/, ''), KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '', PW = process.env.NEW_PASSWORD || '';
const DOMAIN = process.env.AUTH_EMAIL_DOMAIN || 'users.mapehdavnor.altasme.app';
if (!username || !URL_ || !KEY || PW.length < 10) { console.error('Usage: NEW_PASSWORD (10+ characters), SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the environment, then: node tools/reset-password.mjs <username>'); process.exit(1); }
const H = { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' };
const call = async (m, p, b, x = {}) => { const r = await fetch(URL_ + p, { method: m, headers: { ...H, ...x }, body: b ? JSON.stringify(b) : undefined }); const t = await r.text(); return { s: r.status, j: t ? JSON.parse(t) : null }; };
const prof = await call('GET', `/rest/v1/profiles?select=id&username=eq.${encodeURIComponent(username)}`);
if (!prof.j || !prof.j.length) { console.error('No such username.'); process.exit(1); }
const id = prof.j[0].id;
const up = await call('PUT', `/auth/v1/admin/users/${id}`, { password: PW });
if (up.s >= 300) { console.error('Password update failed: HTTP ' + up.s); process.exit(1); }
// The database clears the flag whenever a password changes, so set it again afterwards.
const fl = await call('PATCH', `/rest/v1/profiles?id=eq.${id}`, { must_change_password: true }, { Prefer: 'return=minimal' });
if (fl.s >= 300) { console.error('Could not set must_change_password: HTTP ' + fl.s); process.exit(1); }
console.log(`Password for ${username} reset. They must choose a new one at next sign-in.`);
