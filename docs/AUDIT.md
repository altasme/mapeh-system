# AUDIT: MAPEH Davao del Norte Assessment System

Source audited: `legacy/mapehDavNor.original.html` (2,304 lines, unmodified, kept as the regression baseline).
Spec: `CLAUDE.md` v1.2. Appendix B was the starting register; every row was checked against the code.
Line numbers refer to the legacy file. "Result" says what the build did and how it was checked.

## Register

| ID | Sev | Finding (verified in code) | Disposition | Result |
|----|-----|----------------------------|-------------|--------|
| C1 | Critical | `USER_ACCOUNTS` lines 488-503: 13 accounts with plaintext passwords including Admin. Matches Appendix D exactly | FIX | Removed. Supabase Auth. No password exists in `public/`. QA step 1 and the secret scan confirm |
| C2 | Critical | Line 505 trusts `currentUser` from `sessionStorage`; anyone can edit it to Admin | FIX | Profile is read from `profiles` after sign-in; RLS enforces scope. QA 7: no user object in sessionStorage. RLS matrix passes (local Postgres) |
| C3 | Critical | Lines 2254-2273: cleartext `prompt()` compared to the literal Admin password | FIX | Re-authentication modal (masked field, `signInWithPassword`). QA 5 |
| C4 | Critical | Stored XSS: 206 `${}` interpolations, stored text rendered via `innerHTML` | FIX | `esc()` on every stored or imported string; policy comment above the renderers. QA 4 shows the payload running in the original and not in the port, including `</textarea>` in notes |
| C5 | Critical | `seedDemoData()` lines 661-711 seeded 1,452 unflagged random records | FIX | Removed from runtime. `supabase/seed/demo_records.sql` is deterministic, every row `is_demo = true`, banner shown, SAMPLE DATA line on print |
| H1 | High | SheetJS 0.18.5 known vulnerabilities | FIX | 0.20.3 from `cdn.sheetjs.com` (0.20.4 and later do not exist on that CDN at build time) |
| H2 | High | IndexedDB writes had no error handling | FIX | Every write awaited, `error` checked, success toast only after confirmation. QA 6 (offline: no false success) |
| H3 | High | Baseline edit silently rewrote every matching record | FIX | Count query then confirm "This will change the baseline on N records". QA 6 |
| H4 | High | (migration) PostgREST 1,000-row cap | FIX | Paginated reads. QA 2: all 1,452 rows seen though the stand-in caps at 1,000 |
| H5 | High | CDN scripts without SRI | FIX | Pinned versions with SRI; `tools/verify-sri.sh` re-checks them against the CDNs |
| M1 | Med | Import silently defaults grade, subject, term, MPS 0, baseline 65 | DOC | Preserved (upgrade `importValidation`) |
| M2 | Med | No duplicate detection | DOC | Preserved (upgrade `duplicateDetection`) |
| M3 | Med | "Division MPS" computed two ways (mean of district means of term means vs flat mean). Zero-valued term means are treated as missing | DOC | Preserved. The regression fixture pins both numbers (83.75% vs 84.00%). Client to confirm (star 10) |
| M4 | Med | Unweighted means, no learner counts | DOC | Preserved |
| M5 | Med | Proficiency cutoffs 90/85/80/75 unconfirmed | DOC | Preserved and pinned by the fixture |
| M6 | Med | Least-learned ranking groups exact text | DOC | Preserved |
| M7 | Med | Mixed record grain (district vs school) | DOC | Preserved |
| M8 | Med | Key Stage filter uses `keyStage`; comparative uses grade membership | DOC | Preserved |
| M9 | Med | No edit, single delete, or data export | DOC | Not built (feature flags reserved, unwired) |
| M10 | Med | Supervisor equals Admin | DOC | Preserved in RLS (`app_is_division_user`). Client to confirm (star 8) |
| L1 | Low | Empty groups showed "0.00% Beginning" and "-65.00% Decreased" | FIX | Display only: "No data" or "-". Calculations untouched. QA 3 and 7 |
| L2 | Low | Logout kept filter state | FIX | `signOut()` then reload |
| L3 | Low | Dead `readAsBuffer` branch | FIX | Removed |
| L4 | Low | Placeholder-looking default names print on reports | DOC | Seeded verbatim (star 5); banner stays on; Admin replaces them in Settings |
| L5 | Low | School years start 2025-2026 | DOC | Preserved |
| L6 | Low | Nav items not keyboard operable | FIX | `role=button`, `tabindex=0`, Enter and Space. QA 7 |
| L7 | Low | Logos stored with no size cap | FIX | 500 KB cap with a message |
| R1 | Accepted | CSP needs `'unsafe-inline'` for scripts (inline handlers kept) | Accepted | `esc()` is the real XSS control |
| R2 | Accepted | Original passwords kept by client direction (v1.2). Anyone holding the original file can sign in as any account, including Admin | Accepted | Prototype only. Replace the passwords before any real data goes in |

## Findings added during the build

| ID | Sev | Finding | Disposition |
|----|-----|---------|-------------|
| N1 | Low | Copy says "8 IPED" in the header, Division Summary and several views, but `IPED_OFFERS` has 9 entries, so `SUBJECTS.length` is 58 while the text adds up to 57 | DOC. Left as is because it changes displayed text. One-word fix if the client agrees |
| N2 | Low | Zero MPS treated as "no data" in Division Summary (`v > 0`) | DOC |
| N3 | Low | Import district fallback "Unassigned" cannot exist once districts are a foreign key | FIX per spec 9.2: the file is rejected with row numbers and values |
| N4 | Info | The original `seedDemoData` used `Math.random()`, so sample data was never reproducible | FIX: fixed-seed generator `tools/gen_demo_records.py` |
| N5 | Info | The original app had a render race: a slow async view could overwrite a newer one (seen when changing filters quickly) | FIX as a side effect: each view render is token-guarded |
| N6 | Low | District coordinators are saved with 11 separate updates. RLS forbids a single upsert (no insert policy), so a failure partway can leave some rows saved | Mitigated: results are checked, the screen reloads what the database really holds, and the failed districts are named. Not silent. A single RPC function would make it atomic (upgrade) |
| N7 | Info | supabase-js keeps the session token in the browser's localStorage. This is the library's normal behavior and is what keeps users signed in | Accepted. Output escaping (C4) is the control that protects it |
| N8 | Info | The page `<title>` and a few settings captions said "local browser database". Two captions in Settings were reworded because the database is no longer local | Done |
| N9 | Info | Phone layout: the "Special Programs Matrix" tag in the header is hidden under 640px so the user badge and filters fit on one screen | Done |

## How this was checked

Run `node tools/qa/run_qa.mjs` (needs Playwright and the cached CDN files). 118 checks pass:
seed fidelity against the original, parity of 7 views under 5 filter combinations on the 1,452-row set,
the hand-computed regression fixture, XSS, roles, destructive actions, write errors, 360px layout,
print CSS identity and PDF text identity. The ported app runs against `tools/qa/stub-supabase.js`,
an in-memory stand-in. That proves the application logic. It does not prove Supabase itself: the real RLS
policies are tested by `supabase/tests/rls_matrix.sql` (passes on a local Postgres 16 with a minimal
Supabase shim), and a final browser run against the real project is part of deployment (HANDOVER section 2).

## Added 2026-10-12: Elementary and Secondary coordinators

| ID | Sev | Finding | Disposition |
|----|-----|---------|-------------|
| N10 | High | The original 11 district-wide coordinators could read and write both education levels, so they cannot coexist with a model where a coordinator must never see the other level. | FIX: retired by migration 0004 (`profiles.active = false`, sign-in banned by the provisioning script). Reversible. |
| N11 | High | Initial passwords follow a guessable pattern (`{district_code}@elem` and `@sec`). Whoever signs in first with an unclaimed account chooses its password. | MITIGATED, not removed: database-enforced password gate (`must_change_password`), forced change at first sign-in, password rules, `tools/reset-password.mjs`. Hand the accounts out together and change them at once (HANDOVER section 11). The convention is in the private repository. |
| N12 | Med | A coordinator's reach had to be limited by district AND level on records and on notes. Notes were keyed by district only, so the two coordinators of a district would have shared them. | FIX: `comparative_notes.education_level`, new unique key, new policies. |
| N13 | Med | The forced password change relies on a trigger on `auth.users` (a Supabase-managed schema) to clear the flag. If the trigger were dropped, accounts would stay locked (fails safe, not open). | DOC. The flag is also set again by `tools/reset-password.mjs` after administrative resets. |
| N14 | Low | Unknown grade levels were accepted before. They now have no education level and are refused (database, import and forms). The silent import default of Grade 1 (M1) still applies. | FIX. |
| N15 | Info | "Prepared by" on a coordinator's printed report uses one coordinator name per district, although there are now two coordinators per district. | DOC, awaiting the client's decision. |

## Added 2026-10-14: MAPEH components, grade rules, record editing and deletion

| ID | Sev | Finding | Disposition |
|----|-----|---------|-------------|
| N16 | Med | Grade 1 to 3 records could be filed under Music, Arts, PE or Health, and any grade under any MAPEH area, because learning area was free text. | FIX: database trigger `app_mapeh_rule_problem` (create, and edit when grade or area change), mirrored in forms, imports and templates. IPED, SPA, SPS and SPFL unrestricted. The grade rules are an assumption to confirm with the client. |
| N17 | Med | Old combined MAPEH records (`Music & Arts`, `PE & Health`) cannot be split into the four components. | DOC. Kept, shown, editable and still counted in the MAPEH total; Grade 1 to 3 legacy rows are flagged "Needs correction". Not converted automatically. |
| N18 | Med | Overall MAPEH may not be the plain average of the four components (client question). | Handled by design: overall is its own official record and is never derived. Component and overall MPS are shown side by side. |
| N19 | High | Coordinators could not edit, and edits that bypassed the screen would not have updated `proficiency_level` (the client computed it). | FIX: `proficiency_level` is computed by a trigger from `mps`; edit stamps `updated_by`. |
| N20 | High | Deletion was permanent (Admin/Supervisor, whole school year or everything). | FIX: soft delete with who, when and why; restore for the division team; bulk deletes are soft too; direct DELETE revoked. Permanent purge only from the SQL editor by the database owner. |
| N21 | High | Direct API writes could set any column of a record in scope, including `is_demo` and `created_by`. | FIX: column-level INSERT/UPDATE privileges limit writes to the business columns; delete/restore only through scope-checked, all-or-nothing functions. |
| N22 | Low | The old app sends `is_demo` on insert, which the new privileges refuse. | DOC: deploy 0005 and the matching app together (HANDOVER section 12). |
| N23 | Info | Division Summary averages component figures as a mean of term means (same method as its matrix); Grade Level Breakdown uses flat means like its existing table. | DOC (AUDIT M3 applies to the new tables as well). |

| N24 | Info | N15 (one "Prepared by" name per district although two coordinators exist) | RESOLVED by migration 0006: coordinator name and position are stored per level and reports use the level in view. With both levels in view and different details, both names print. |
| N25 | Low | All dashboard bars were one colour, so districts, tracks and components could not be told apart by colour. | FIX (display only): shared palette, contrast and distance checked by the test suite; values unchanged. |
| N26 | Med | Competency entries could not be corrected; a direct API update of `least_learned` was possible for any record in scope, with no shape check. | FIX: edit through a permission-respecting function with validation and a stale-edit check; the table now refuses a non-list value. |
| R3 | Accepted | By client direction for the testing phase: original passwords for Admin and Supervisor, guessable initial passwords for the 22 coordinators, no password-change feature and no forced change. Supersedes the mitigation in N11. | Accepted while only sample data is held. Must be reversed before real data (HANDOVER section 15). |
