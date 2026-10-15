# HANDOVER: MAPEH Davao del Norte Assessment System · Test Deployment

**Built by:** Altaventures Business Development Services
**Handover date:** 2026-10-11 (live)  ·  **Spec version built:** v1.2
**Test URL:** https://mapeh-system.pages.dev  ·  **Repo:** https://github.com/altasme/mapeh-system (private)

## 1. What was delivered
- Existing app, unchanged in behavior, ready for Cloudflare Pages. All 9 views, formulas, print layout and Excel template preserved.
- Shared Supabase database design replacing per-browser storage: migrations, seeds, and a deterministic sample data set.
- Supabase login replacing hardcoded accounts. District access is enforced in the database (RLS), not only in the page.
- Code audit: docs/AUDIT.md (29 register entries: 15 fixed in code, 12 documented for the upgrade, 2 accepted risks; plus 9 findings added during the build).
- Visual polish: responsive layout with phone drawer menu, loading / empty / error states, toasts, test-environment banner, re-authentication modal, keyboard-operable navigation. Redesigned on 2026-10-11 (see DESIGN.md).
- Download CSV (Admin and Supervisor only, in the page header): downloads every record in the database as one CSV, sorted by school year, district, term and grade. Columns use the import template's names so the file can be re-imported, plus Proficiency Level, Sample Data, Record ID and Date Added. Notes, settings and users are not included.
- Division signatories in Settings are laid out as three aligned rows (Prepared by, Checked by, Noted by), each with Name and Position.
- Placeholders shipped on purpose: `public/config.js` and `public/_headers` contain `[PROJECT-REF]` and `[PUBLISHABLE_KEY]` until the Supabase project exists. The site shows "not configured yet" on the login screen until they are filled.
- Verification: 118 automated checks against an in-memory stand-in (`node tools/qa/run_qa.mjs`), the RLS matrix on a local Postgres, and, against the LIVE project and the DEPLOYED site (real CSP, real CDN scripts with SRI): 27 of 27 access-rule checks as real signed-in users (`tools/verify-live.mjs`), 20 of 20 browser checks (`LIVE_URL=... node tools/qa/live_smoke.mjs`), 15 of 15 write-path checks with full restore (`tools/qa/live_writes.mjs`: manual entry, valid and invalid Excel imports, baseline edit, notes, settings), and all 13 accounts signing in. Not tested live: the 360px layout and print output (checked on the stand-in only) and a client walkthrough.

## 2. Run & deploy
No build step.

**One-time Supabase setup: DONE on project `yesnxycbzwaaugqbwowd` (steps 1 to 5 below, run 2026-10-11). Kept for rebuilding.**
1. Create the project. Authentication > Providers > Email: turn **off** "Allow new users to sign up" and "Confirm email".
2. SQL editor: paste and run `supabase/setup_all.sql` (migrations 0001 to 0003 plus the districts and settings seeds in one file).
3. Create the Admin and Supervisor accounts: from a terminal run
   `SUPABASE_URL=https://<ref>.supabase.co SUPABASE_SERVICE_ROLE_KEY=<service key> node tools/provision-accounts.mjs`
   (The Elementary and Secondary coordinators are created by `tools/provision-level-coordinators.mjs`; see section 11, which also gives the order to follow on a project that already exists.)
   (add `--dry-run` first to preview). It reads each password from `legacy/mapehDavNor.original.html`, never prints it, and also inserts the profiles rows. Keep the service-role key out of chat, files and git.
4. Load the 1,551 flagged sample rows (current MAPEH structure): `node tools/load-demo-records.mjs` (same env vars as step 3; `supabase/seed/demo_records.sql` is the equivalent SQL).
5. Check the access rules: `supabase/tests/rls_matrix.sql` in the SQL editor (six `PASS` notices, rolls back) and `node tools/verify-live-levels.mjs` over the public API (all 22 coordinators, Admin, Supervisor and the retired accounts).

**Cloudflare Pages**
6. `public/config.js` and `public/_headers` already hold the project URL, publishable key and ref (done).
7. DONE: Cloudflare Pages project `mapeh-system` from this repo (framework None, no build command, output `public`). Deploys on every push to `main`.
8. Supabase Authentication > URL Configuration: Site URL must be https://mapeh-system.pages.dev (to be confirmed by Altaventures; it is not readable through the API).
9. **Real-project checks before handing over:** sign in as each of the 13 accounts; confirm a coordinator sees only their district; run one Excel import, one manual entry, one baseline edit; print one report; run `tools/verify-sri.sh`.

- Config: public/config.js (public values only). Pinned versions: supabase-js 2.117.3, SheetJS 0.20.3, Chart.js 4.4.1 (all with SRI).
- Database changes: supabase/migrations, applied in order.
- Resetting a password: Authentication > Users > the user > Send password recovery is NOT available (no real mailbox). Use "Update user" and set a new password directly.

## 3. Where to edit
- Signatories, header and footer text, logos, coordinator names: Settings & Branding (Admin or Supervisor), no developer needed.
- Subjects, grades, key stages, school years: constants block in public/index.html (developer).
- Districts list: `districts` table (developer).

## 4. Upgrade activation map
| Flag (`APP_CONFIG.features`) | Now | Turns on | Client inputs needed |
|---|---|---|---|
| `recordEditing` | false | Edit and delete individual records | Who may edit what, after which deadline |
| `excelDataExport` | false | Export filtered, authorized records to .xlsx | Required column layout |
| `importValidation` | false | Row-level validation report, no silent defaults, partial accept | Rules for missing fields |
| `duplicateDetection` | false | Reject or update on re-import | Agreed record identity |
| `selfServicePassword` | true (change-password screen built 2026-10-12; reset-by-email is still not built) | Reset-by-email flow | Real emails |
| (new) | n/a | Weighted MPS, competency standard, school master list, realtime, user management UI, offline use, production hardening and backups | Methodology confirmation, budget |

All flags are reserved and unwired.

## 5. Outstanding blocking inputs
- Star 5: coordinator names, signatories and footer contact are the client's original defaults (they look like placeholders). The test banner stays on until an Admin enters real values.
- Star 8: Supervisor has full Admin powers, as in the original. Client to confirm.
- Star 10: division MPS is computed two ways in the original (AUDIT M3). Not changed. Client to confirm the method.
- N1 in the audit: copy says "8 IPED" but there are 9 IPED offers. Client to confirm the wording.
- Star 7: assumed no real data in any browser. If any exists, the legacy export tool (spec 9.8) must be built before cutover.
- Star 9: default `*.pages.dev` address; custom domain not set.

## 6. Data-integrity status
- [x] Demo rows present: 1,452 (loaded before the MAPEH restructure, so they use the legacy combined areas; to switch to the current structure purge and reload, see section 12). Purge: `delete from public.assessment_records where is_demo;`
- [x] Test banner on (`environment: "test"`)
- [ ] Coordinator names and signatories replaced with real values (not done: star 5)
- [x] Real data: not applicable (prototype, star 4). Real data requires an upgrade plus SDO authorization

## 7. Account administration
- Create a user: Supabase Dashboard > Authentication > Add user (auto-confirm) with email `username@users.mapehdavnor.altasme.app`, then:
  ```sql
  insert into public.profiles (id, username, display_name, role, district_id)
  select u.id, 'newuser', 'Display Name', 'district_coordinator', (select id from public.districts where name = 'Carmen')
  from auth.users u where u.email = 'newuser@users.mapehdavnor.altasme.app';
  ```
- Reset a password: Authentication > Users > the user > Update user > new password.
- Disable a user: Authentication > Users > the user > Ban user (or delete the user; the profile is removed with it).
- Current accounts after section 11 is applied: 2 division accounts (Admin, Supervisor; their passwords are still the ones in the client's original file) and 22 level coordinators (initial passwords per section 11, replaced by their owners at first sign-in). The original 11 district-wide coordinators are retired, not deleted. Recommend new passwords before any real data goes in (AUDIT R2).

## 8. Accounts & infrastructure (pointers, NOT secrets)
- Cloudflare Pages: Altaventures account / project `mapeh-system` (https://mapeh-system.pages.dev)
- Supabase: Altaventures dedicated account / project ref `yesnxycbzwaaugqbwowd` / region ap-southeast-1 (confirm in dashboard) / plan TBD
- Inactivity pause behavior and backups: check the plan at creation. Free projects have historically paused after about a week of inactivity and have no automated backups. Record the chosen plan here, and take a manual export (Dashboard > Database > Backups, or `pg_dump`) before any client session if the plan has no backups.
- Repo: https://github.com/altasme/mapeh-system

## 9. Known limitations
- No record editing or single-record delete; no Excel (.xlsx) data export. The CSV download covers assessment records only.
- Import applies silent defaults; one bad row rejects the whole file; no duplicate detection.
- Division MPS differs between Division Summary and Dashboard (different averaging, AUDIT M3).
- Inline script handlers require 'unsafe-inline' in CSP (AUDIT R1, accepted).
- Saving all 11 district coordinators is 11 separate updates; a failure is reported and the screen reloads the truth (AUDIT N6).
- Each view reloads its data when opened (about two requests per 1,000 rows). Fine at test volumes.
- The original passwords are still in use (AUDIT R2).

## 10. Recommended next steps
- Before the client's first session: confirm the Site URL (step 8), do a short walkthrough with the client on a phone and a laptop, then send the Test URL. Rotate the Supabase database password, secret key and service-role key (they were shared in a chat transcript).
- Ask the client to confirm: real coordinator names and signatories, whether Supervisor should keep Admin powers, how division MPS should be averaged, and the "8 IPED" wording.
- When the client is ready for real data: change all passwords, move to a paid plan with backups, purge the sample rows, set `environment` to "production", and scope the upgrade items in section 4.

## 11. Elementary and Secondary coordinators (added 2026-10-12)

**What changed.** Each district now has one Elementary and one Secondary coordinator account (22 in all). A coordinator sees and enters only records of their own district AND their own education level. Education level comes from the grade: Grade 1 to 6 is Elementary, Grade 7 to 12 is Secondary. Admin and Supervisor still see both levels, and gain an Education Level filter. The separation is enforced by Row Level Security in the database (`supabase/migrations/0004_education_levels.sql`), not by the page: records, notes, imports, deletes and reads all go through the same rule. The page only hides what the database would refuse.

**Accounts.**
| | Username | Initial password |
|---|---|---|
| Elementary | `{district_code}_elemcoord` | `{district_code}@elem` |
| Secondary | `{district_code}_seccoord` | `{district_code}@sec` |

District codes are the ones the original usernames already used: asuncion, dujali, carmen, kapalonge, kapalongw, newcorella, sanisidro, stotomase, stotomasw, talaingod, langilan. **Confirm these are the approved codes.** They are listed in `tools/provision-level-coordinators.mjs`.

**Passwords are initial credentials only.**
- Every new account is created with `must_change_password = true`. While that is set the database returns no records, notes or anything else and refuses writes, even to someone calling the data API directly. The app forces the change at first sign-in (10 or more characters, a letter and a number, no username or district name, nothing obvious) and the database clears the flag only when the Auth password really changes.
- The initial passwords are built from the convention at run time by the provisioning script. They are not in `public/`, not in the app, and not printed. The convention itself is visible to anyone who can read this repository (keep it private).
- Risk to manage: the pattern is guessable, so whoever signs in first with a new account sets its password. Hand the accounts out together, ask each coordinator to sign in right away, and treat an account whose owner reports being locked out as compromised: reset it with `tools/reset-password.mjs`.
- Any signed-in user can change their own password with the "Password" button (current password required). An administrative reset (`tools/reset-password.mjs <username>`, new temporary password from the environment) makes the person choose again at next sign-in.
- Also set the Supabase minimum password length to 10 or more (Authentication, Providers, Email) and, on a plan that offers it, turn on leaked-password protection. The app enforces its own rules; the server setting is the backstop.

**Order of work on the live project (do not skip or reorder).**
1. Merge nothing yet. The new app version needs the new database; the old one keeps working until the SQL below is run, then fails to save notes (their key changed).
2. In the Supabase SQL editor run `supabase/migrations/0004_education_levels.sql` (an existing project) or `supabase/setup_all.sql` (a new one). The migration also retires the original district-wide coordinators (`profiles.active = false`; set it back to true to restore one).
3. Merge `feature/education-levels` into `main` (Cloudflare Pages redeploys in about a minute). Between steps 2 and 3, saving comparative notes fails; nothing else is affected.
4. `SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node tools/provision-level-coordinators.mjs --dry-run`, then without `--dry-run`. This creates the 22 accounts and bans sign-in for the original 11.
5. `node tools/verify-live-levels.mjs` (needs the publishable key as well). It tests every one of the 22 accounts against the real project, lifts and restores each account's password gate itself, and cleans up after itself. Do not release the accounts until it reports 0 failed.
6. Hand the accounts out (initial passwords delivered privately) and ask each owner to sign in and choose a password.

**What was verified, and what was not.** The access rules pass `supabase/tests/rls_matrix.sql` on Postgres 16 both as an upgrade of the existing schema and as a fresh install (Admin, Supervisor, four coordinators across two districts and both levels, a retired account, an initial-password account, signed out). The app passes 212 browser checks against an in-memory stand-in that mirrors those rules, including all 22 accounts, cross-level attempts through the app and through the data API, imports, the forced password change and the CSV. **Not yet run against the live project:** steps 4 and 5 above. `verify-live-levels.mjs` has been syntax-checked only.

**Decisions to confirm.**
- Education level is derived from the grade (not chosen separately), so a record can never claim a level that its grade contradicts. A grade outside Grade 1 to 12 is refused.
- Superseded by section 12: coordinators can now edit and delete (recoverably) within their own district and level; only Admin and Supervisor can restore.
- Comparative notes are now filed per district and level. A division user with the Education Level filter on All Levels writes "all levels" notes that coordinators cannot see.
- The printed "Prepared by" for a coordinator still comes from the single coordinator name saved for the district in Settings. There is now one Elementary and one Secondary coordinator per district, so you may want two names per district. Not built; say if you want it.
- The Key Stage / Grade mismatch noted in AUDIT M8 is unchanged: the level follows the grade.

## 12. MAPEH components, grade rules, and record editing / deletion (added 2026-10-14)

**What changed.**
1. **Component breakdown.** Grade Level Breakdown now has a second table, "MAPEH Components by Grade Level": Music, Arts, Physical Education (PE), Health and Overall MAPEH, per grade. The Division Summary has "MAPEH Components by District" (mean of term means, the method of the matrix above it). The Dashboard has a "MAPEH Components and Overall MAPEH" chart and the Comparative sheet has a row per component under the MAPEH total. These sections appear when records under the new structure exist; with only old records the screens and printouts are exactly as before. The existing grade table, KPI and totals were not changed.
2. **Overall MAPEH is its own official record.** It is entered or imported as learning area `MAPEH - Overall`. It is never calculated from the four components (the system makes no assumption about how the official overall is derived). All figures are unweighted means of record MPS, like the rest of the system (AUDIT M4).
3. **Grade rules, enforced by the database** (a trigger, so the app, Excel imports and direct API calls all obey it; the app repeats the same rules to give early, readable messages):
   | Grades | Allowed MAPEH records |
   |---|---|
   | 1 to 3 | `MAPEH - Overall` only (no Music, Arts, PE, Health, and no combined areas) |
   | 4 to 10 | `MAPEH - Overall` plus `MAPEH - Music`, `Arts`, `PE`, `Health` (combined areas no longer accepted) |
   | 11 to 12 | no MAPEH records |
   IPED, SPA, SPS and SPFL are not restricted (IPED keeps its own MAPEH subjects, `IPED - MAPEH (Music & Arts)` and `(PE & Health)`, in every grade). **Please confirm these grade rules with the client.** They are one function (`app_mapeh_rule_problem`) plus its copy in the app (`mapehRuleProblem`).
4. **Old combined records are kept.** `MAPEH - Music & Arts` and `MAPEH - PE & Health` rows stay in the database, are shown everywhere, are editable (score, school, etc.), and still count toward the MAPEH totals exactly as before (the "MAPEH total" counts overall plus legacy records, never the four components, so nothing is counted twice). The rule is enforced when a row is created or when its grade or learning area is changed, so an old Grade 1 to 3 combined record is not deleted: it is flagged "Needs correction" in Manage Records. Grade 4 to 10 legacy rows are tagged "Legacy area".
5. **Manage Records** (new menu item). A searchable, paged list of the records in the user's scope (it follows the filter bar) with Edit and Delete. The edit form revalidates everything (ranges, grade and level, MAPEH rules); the database checks again. Delete asks for confirmation and an optional reason. Deleted records are hidden from every view, summary, chart, report and CSV, but kept. Admin and Supervisor have a "Deleted records" tab with Restore.
6. **Who may do what (enforced by Supabase, not by the screen).** Coordinators: edit and delete inside their own district AND education level. Admin and Supervisor: everywhere, plus restore, delete by school year and delete all (now also soft). Direct DELETE on the table is removed for everyone but the database owner. Writes are limited to the business columns, so `is_demo`, `created_by`, `deleted_*` and `updated_by` cannot be set through the API. Deletion and restore go through functions that check scope and are all-or-nothing (a batch containing one record outside your scope deletes nothing).
7. **Audit trail.** `proficiency_level` is now computed by the database from the MPS (same 90/85/80/75 scale), so an edit can never leave it stale. Every edit stamps `updated_by`/`updated_at`. Every change is in `audit_log` with the old and new row; soft deletes and restores are labelled `SOFT_DELETE` and `RESTORE` and carry who, when and the reason (`deleted_by`, `deleted_at`, `delete_reason` on the record). Admin reads it in the Supabase dashboard (no screen).

**Order of work on the live project.**
1. Run `supabase/migrations/0005_mapeh_components_and_record_controls.sql` in the SQL editor (it needs 0004 first; a new project just runs `setup_all.sql`). Then run `supabase/tests/rls_matrix.sql` (seven PASS notices).
2. Merge `feature/mapeh-components-edit-delete` (it contains the education-level work too) into `main`. **Do this right after step 1:** the previous app version sends `is_demo` on insert, which the new column privileges refuse, so saving new records from the old page fails until the new page is live. Reading is unaffected.
3. Optional: to show the new structure in the sample data, run `delete from public.assessment_records where is_demo;` and then `node tools/load-demo-records.mjs`. The sample rows loaded earlier use the old combined areas; they stay valid and visible but the component tables stay empty until components are entered.

**Verified.** `supabase/tests/rls_matrix.sql` on Postgres 16 as an upgrade and as a fresh install: every grade/area combination of the rule table, rejection on create and on edit, grandfathered old rows, computed proficiency, editor stamp, soft delete/restore/audit labels, atomic batches, bulk RPCs division-only, direct DELETE and protected columns refused, plus all the earlier level checks. The browser suite (`node tools/qa/run_qa.mjs`) covers the component figures against hand-computed means, the form/import/template rules, edit and delete in the screen, reports reflecting edits and deletions, and the coordinator direct-API attempts. The browser suite runs against an in-memory stand-in for Supabase; the SQL tests are what prove the real policies. Not yet run against the live project (needs step 1 first).

**Decisions to confirm.**
- The grade rules above, and that Grade 11 to 12 have no MAPEH.
- That Overall MAPEH is reported by districts and not derived (the system never computes it from the components).
- Whether old combined records should be corrected by the districts (use Manage Records: change the area, or the grade) or left as history.
- Coordinators can now delete (recoverably) within their scope. Say if deletion should be limited to Admin and Supervisor; it is one policy and one function check.
- Hard deletion is not available from the app. Permanent removal is done by Altaventures in the SQL editor if ever needed.

## 13. Coordinators by education level (added 2026-10-15)

**What changed.** Settings & Branding, "District Coordinator & Position Management": each district (existing order) is now one card with the district name as its heading and two subsections beneath it, **Elementary Coordinator** and **Secondary Coordinator**, each with Coordinator Name and Designated Position / Title. Save works as before (one Save button, checked per district, success only when the database confirms).

**Storage.** `districts` has four new columns: `elem_coordinator_name`, `elem_coordinator_position`, `sec_coordinator_name`, `sec_coordinator_position` (migration `0006_coordinators_by_level.sql`). Existing information is preserved: both levels start with the district's current name and position. The old columns stay in the table, untouched and no longer read by the app. Only Admin and Supervisor can change them (existing policy; checked in `rls_matrix.sql`).

**Reports.** The printed "Prepared by" (name and position), the District Profile header, the Division Summary coordinator column and the per-district notes use the coordinator of the level being shown (a coordinator's own level, or the Education Level filter). With both levels in view: one name if both levels have identical details (so nothing changes until the two are edited apart), otherwise both, e.g. "Elena Elementary / Sam Secondary".

**To deploy.** 1) Run `supabase/migrations/0006_coordinators_by_level.sql` in the SQL editor (the current live app keeps working after it). 2) Merge `feature/coordinators-by-level` into `main`. Doing it in the other order makes the new Settings page and every view fail to load, because the new app reads the new columns. 3) Open Settings and enter the Elementary and Secondary names.
