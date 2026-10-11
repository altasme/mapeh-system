#!/usr/bin/env node
// Loads the 1,452 flagged sample records (is_demo = true) through the REST API, in batches.
// Run AFTER setup_all.sql and tools/provision-accounts.mjs (created_by points at the admin profile).
//   SUPABASE_URL=https://<ref>.supabase.co SUPABASE_SERVICE_ROLE_KEY=<service_role JWT> node tools/load-demo-records.mjs
// Refuses to run if any demo rows already exist (so it cannot double the data). Never prints the key.
import { execSync } from 'child_process';
import path from 'path';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const URL_ = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
if (!URL_ || !KEY) { console.error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the environment.'); process.exit(1); }
const H = { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' };
const get = async p => { const r = await fetch(URL_ + p, { headers: { ...H, Prefer: 'count=exact' } }); return { status: r.status, json: await r.json(), range: r.headers.get('content-range') }; };

const demo = JSON.parse(execSync(`python3 ${ROOT}/tools/gen_demo_records.py --json`, { maxBuffer: 1 << 26 }).toString());
const d = await get('/rest/v1/districts?select=id,name');
const a = await get('/rest/v1/profiles?select=id&username=eq.admin');
if (d.status !== 200 || !d.json.length || a.status !== 200 || !a.json.length) { console.error('Districts or the admin profile are missing. Run setup_all.sql and provision-accounts.mjs first.'); process.exit(1); }
const existing = await get('/rest/v1/assessment_records?select=id&is_demo=eq.true&limit=1');
if (existing.json.length) { console.error('Demo rows already exist. Purge first: delete from public.assessment_records where is_demo;'); process.exit(1); }

const did = Object.fromEntries(d.json.map(x => [x.name, x.id]));
const rows = demo.map(r => ({ sy: r.sy, term: r.term, district_id: did[r.district], school: r.school, key_stage: r.keyStage, grade_level: r.gradeLevel,
  learning_area: r.learningArea, baseline_mps: r.baselineMps, mps: r.mps, pct75: r.pct75, proficiency_level: r.proficiencyLevel,
  least_learned: r.leastLearned, is_demo: true, created_by: a.json[0].id }));
for (let i = 0; i < rows.length; i += 250) {
  const r = await fetch(URL_ + '/rest/v1/assessment_records', { method: 'POST', headers: { ...H, Prefer: 'return=minimal' }, body: JSON.stringify(rows.slice(i, i + 250)) });
  if (r.status >= 300) { console.error(`Batch at ${i} failed: HTTP ${r.status} ${(await r.text()).slice(0, 200)}`); process.exit(1); }
}
const n = await get('/rest/v1/assessment_records?select=id&is_demo=eq.true&limit=1');
console.log(`Loaded ${rows.length} sample records. Database reports ${n.range} (is_demo rows).`);
