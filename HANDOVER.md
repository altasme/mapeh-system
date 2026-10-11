# HANDOVER: MAPEH Davao del Norte Assessment System · Test Deployment

**Built by:** Altaventures Business Development Services
**Handover date:** 2026-10-11 (build complete; deployment steps in section 2 still to be done)  ·  **Spec version built:** v1.2
**Test URL:** TBD (set when the Cloudflare Pages project is created)  ·  **Repo:** https://github.com/altasme/mapeh-system (private)

## 1. What was delivered
- Existing app, unchanged in behavior, ready for Cloudflare Pages. All 9 views, formulas, print layout and Excel template preserved.
- Shared Supabase database design replacing per-browser storage: migrations, seeds, and a deterministic sample data set.
- Supabase login replacing hardcoded accounts. District access is enforced in the database (RLS), not only in the page.
- Code audit: docs/AUDIT.md (29 register entries: 15 fixed in code, 12 documented for the upgrade, 2 accepted risks; plus 9 findings added during the build).
- Visual polish: responsive layout with phone drawer menu, loading / empty / error states, toasts, test-environment banner, re-authentication modal, keyboard-operable navigation.
- Placeholders shipped on purpose: `public/config.js` and `public/_headers` contain `[PROJECT-REF]` and `[PUBLISHABLE_KEY]` until the Supabase project exists. The site shows "not configured yet" on the login screen until they are filled.
- Verification: 118 automated checks (`node tools/qa/run_qa.mjs`) and the RLS matrix on a local Postgres. These ran against an in-memory stand-in for Supabase, not the real project. Section 2 lists the real-project checks still to do.

## 2. Run & deploy
No build step.

**One-time Supabase setup (Altaventures account, region Singapore, ap-southeast-1)**
1. Create the project. Authentication > Providers > Email: turn **off** "Allow new users to sign up" and "Confirm email".
2. SQL editor, in order: `supabase/migrations/0001_schema.sql`, `0002_rls.sql`, `0003_audit.sql`, then `supabase/seed/districts.sql`, `settings.sql`.
3. Create the 13 accounts: from a terminal run
   `SUPABASE_URL=https://<ref>.supabase.co SUPABASE_SERVICE_ROLE_KEY=<service key> node tools/provision-accounts.mjs`
   (add `--dry-run` first to preview). It reads each password from `legacy/mapehDavNor.original.html`, never prints it, and also inserts the profiles rows. Keep the service-role key out of chat, files and git.
4. SQL editor: `supabase/seed/demo_records.sql` (1,452 sample rows, all flagged).
5. SQL editor: `supabase/tests/rls_matrix.sql`. Expect five `PASS` notices (it rolls back).

**Cloudflare Pages**
6. Edit `public/config.js` (project URL, publishable key) and `public/_headers` (project ref in `connect-src`). Commit.
7. Create the Pages project from this repo: framework preset None, build command empty, output directory `public`. Deploys on every push to `main`.
8. In Supabase Authentication > URL Configuration set Site URL to the Pages URL.
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
| `selfServicePassword` | false | Change-password and reset-by-email flows | Real emails |
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
- [ ] Demo rows present: 1,452 once `demo_records.sql` is loaded. Purge: `delete from public.assessment_records where is_demo;`
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
- Current accounts: 13 (1 admin, 1 supervisor, 11 district coordinators). Passwords are the ones already defined in the client's original file; nothing new was distributed. Recommend new passwords before any real data goes in (AUDIT R2).

## 8. Accounts & infrastructure (pointers, NOT secrets)
- Cloudflare Pages: Altaventures account / project name TBD
- Supabase: Altaventures dedicated account / project ref TBD / region ap-southeast-1 / plan TBD
- Inactivity pause behavior and backups: check the plan at creation. Free projects have historically paused after about a week of inactivity and have no automated backups. Record the chosen plan here, and take a manual export (Dashboard > Database > Backups, or `pg_dump`) before any client session if the plan has no backups.
- Repo: https://github.com/altasme/mapeh-system

## 9. Known limitations
- No record editing or single-record delete; no Excel data export.
- Import applies silent defaults; one bad row rejects the whole file; no duplicate detection.
- Division MPS differs between Division Summary and Dashboard (different averaging, AUDIT M3).
- Inline script handlers require 'unsafe-inline' in CSP (AUDIT R1, accepted).
- Saving all 11 district coordinators is 11 separate updates; a failure is reported and the screen reloads the truth (AUDIT N6).
- Each view reloads its data when opened (about two requests for 1,452 rows). Fine at test volumes.
- The original passwords are still in use (AUDIT R2).

## 10. Recommended next steps
- Before the client's first session: complete section 2 steps 1 to 9 and send the Test URL.
- Ask the client to confirm: real coordinator names and signatories, whether Supervisor should keep Admin powers, how division MPS should be averaged, and the "8 IPED" wording.
- When the client is ready for real data: change all passwords, move to a paid plan with backups, purge the sample rows, set `environment` to "production", and scope the upgrade items in section 4.
