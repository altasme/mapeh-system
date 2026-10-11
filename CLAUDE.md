# CLAUDE.md: MAPEH Davao del Norte Assessment System (Existing App: Test Deployment)

> Build spec. **Single source of instruction for this build.** When this file and any client doc (including the original `MAPEH-DAVAO-DEL-NORT.txt` brief) conflict, **this file wins**: note the conflict, proceed.
> **Client:** SDO Davao del Norte, MAPEH / Special Programs assessment team  ·  **Builder:** Altaventures Business Development Services
> **One line:** Take the client's existing single-file assessment consolidation app online for testing, backed by Supabase, without changing what it does.
> **Scope: this engagement only.** Four deliverables were offered and accepted: (1) visual improvement, (2) code audit, (3) Cloudflare Pages deployment, (4) Supabase. The client has said: **keep the app as it is**. Expansion happens only when the client asks for an upgrade (§16).

**v1 · 2026-10-10**: Initial build spec. Supersedes the original brief's §3 (UI polish), §7 (import validation, export), §8 (migration), and §13 (scope). Those features are now either reduced to the "as is" minimum or moved to the upgrade map (§16).

**v1.1 · 2026-10-10**: Hard launch gates ★1 to ★4 resolved (Altaventures-owned dedicated Supabase account; the 13 accounts in the original code; usernames from the code as login IDs; prototype with sample data only). Account table added as Appendix D. Supersedes v1 §2 hard-gate table, §2.1 rows for `[AUTH_EMAIL_DOMAIN]` and demo records, §8.4.

**v1.2 · 2026-10-10**: Client direction: **keep the existing passwords.** Each account uses the password already defined for it in the original code. Supersedes v1.1 password paragraph in §2, §8.4 steps 1 and 3, and the Appendix D note. Residual risk recorded as R2 (Appendix B).

---

## 0. Prime directives

1. **Preserve, don't rebuild.** The app stays a single HTML file with its current views, workflows, labels, formulas, print layout, and Excel template. No framework migration (no React, no Vite, no TypeScript conversion), no restructuring into modules, no renaming of existing functions unless a change in this spec requires it.
2. **"As is" does not include the security holes.** Replacing hardcoded logins with Supabase Auth, enforcing district access with Row Level Security, and escaping rendered text are part of the Supabase and code-audit deliverables the client accepted. They change no workflow the client sees. They are mandatory, not optional polish.
3. **Never change a calculation.** MPS averages, proficiency thresholds (`getPL`), variance, consolidated totals, and least-learned ranking keep their exact current logic. Questionable calculations are **documented** in `docs/AUDIT.md` (Appendix B), never "fixed".
4. **Data integrity beats convenience.** A save is only reported as successful when Supabase confirms it. Demo data is always flagged and visibly labeled. No silent partial writes.
5. **A handover file is mandatory (§18 + Appendix A).** The build is not done until `HANDOVER.md` exists and is complete.

---

## 1. Scope: in this engagement vs upgrade

| | **This engagement: BUILD NOW** | **Upgrade: DO NOT BUILD** |
|---|---|---|
| Nature | Existing app, online, shared database, hardened, polished | New features or changed behavior |
| Examples | Supabase Auth + RLS, data layer swap from IndexedDB/localStorage to Supabase, XSS escaping, SheetJS upgrade, responsive layout, loading/error/empty states, Cloudflare Pages deploy, audit report | Record editing and single-record delete, Excel **data** export, import validation and duplicate detection, weighted MPS, competency code normalization, user management UI, self-service password change, realtime, offline sync |
| Data | Same record shape as today, stored in Supabase | Schema changes beyond the mirror in §7 |

**Hard rule for the build assistant:** if you are about to add a screen, a column to a report, a new filter, or change a number the app displays (other than empty-state handling, §9.6), stop. It is an upgrade. Flag and defer.

---

## 2. Blocking inputs: resolve before / during build

### Hard launch gates: RESOLVED (v1.1)

| # | Item | Decision | Consequence for the build |
|---|------|----------|---------------------------|
| ★1 | Account ownership | **Altaventures-owned, on a dedicated Supabase account** created for this client | Altaventures controls data, billing, and keys. Transfer to the client is an upgrade-time task. Cloudflare Pages: Altaventures' account (house standard) unless told otherwise |
| ★2 | User accounts | **Exactly the 13 accounts in the original code**, same display names, roles, and districts | Provision per Appendix D. No additional users |
| ★3 | Login identifier | **The usernames from the code.** Each maps to `username@users.mapehdavnor.altasme.app` (mailbox never used; no DNS needed) | Login screen unchanged. Password resets are done by Altaventures in the Supabase dashboard (no email reset flow) |
| ★4 | Data during testing | **Prototype: sample data only** | Load `demo_records.sql` (all `is_demo = true`), keep the test banner on, keep `environment: "test"`. Real assessment data stays out until the client upgrades and authorizes production hosting |

**Passwords (client direction, v1.2):** keep the passwords the client defined. Each Supabase Auth user is created with the password already set for that username in the original `USER_ACCOUNTS`. What changes is **where** they live: Supabase stores them hashed, and they are removed from the page source, so the deployed site no longer publishes them. Accepted residual risk: anyone holding the client's original file knows every password, including Admin's (Appendix B, R2).

### Content blockers (can ship as labeled placeholders)

| # | Item | Why it matters | Default if unresolved |
|---|------|----------------|------------------------|
| ★5 | District coordinator names, division signatories, footer contact details | Current defaults look like placeholders (several are well-known public or fictional names) and print on official-looking reports | Seed the client's existing defaults verbatim (client said keep as is). The test-environment banner (§12) stays on until an Admin sets real names in Settings |
| ★6 | Confirmed district list | Districts become a database table that all records reference | Seed the existing 11 districts verbatim |
| ★7 | Existing real data in any coordinator's browser | IndexedDB data does not move to Supabase on its own | Assume none for the test deployment. If any exists, build the legacy export tool (§9.8) before cutover |
| ★8 | Supervisor permissions | Currently identical to Admin (settings, branding, bulk delete) | Preserve as is. Recorded as an open question in `AUDIT.md` |
| ★9 | Custom domain | Cosmetic for testing | Use the default `*.pages.dev` URL |
| ★10 | MPS methodology confirmation | Three views compute "division MPS" differently; averages are unweighted | Not blocking. Documented in `AUDIT.md` M3/M4; no formula changes |

**Rule:** where a content blocker is unresolved, ship the default and make it visible as a placeholder or test-environment notice. Never present demo data or placeholder names as real.

### 2.1 Placeholder Registry

| Token / value | Where it lives | Placeholder until | Replace with |
|---------------|----------------|-------------------|--------------|
| `[PROJECT-REF]` | `public/config.js` `supabaseUrl`, `public/_headers` CSP | ★1 | Real Supabase project ref |
| `[PUBLISHABLE_KEY]` | `public/config.js` | ★1 | Supabase publishable (anon) key. **Never** the service-role key |
| `[PROJECT-REF]`, `[PUBLISHABLE_KEY]` source | Dedicated Altaventures Supabase account (★1) | Project creation in M1 | Values from the new project's API settings |
| `authEmailDomain` | `public/config.js` | **Resolved (★3)** | `users.mapehdavnor.altasme.app` |
| Coordinator names and positions | `districts` table seed | ★5 | Real names, set by Admin in Settings |
| Signatories, header lines, footer contact | `app_settings` seed | ★5 | Real values, set by Admin in Settings |
| Print logos (header + 3 footer) | `app_settings.data` | ★5 | Client-uploaded images (none exist today; print shows no logo until uploaded) |
| Demo assessment records | `assessment_records` where `is_demo = true` | **Loaded by design (★4: prototype)** | Purged with one SQL statement only when the client upgrades to real data (Appendix A §6) |
| `APP_CONFIG.environment = "test"` | `public/config.js` | Client acceptance | `"production"` (removes the banner) |

---

## 3. Tech stack (LOCKED for this engagement)

| Layer | Choice |
|---|---|
| App | **Existing single HTML file, vanilla JS, kept as is.** Deviation from the house React/Vite/TS stack is intentional: the client asked for no rebuild |
| Charts / Excel | Chart.js 4.4.1 (keep). SheetJS **upgraded** from 0.18.5 to the latest patched 0.20.x from `cdn.sheetjs.com` (0.18.5 has known prototype-pollution and ReDoS issues when parsing crafted files). Verify the current version at build time |
| Database + Auth | Supabase (Postgres + Auth), region **Singapore (ap-southeast-1)** |
| Supabase client | `@supabase/supabase-js` v2 UMD build from jsDelivr, **exact version pinned** with SRI. Client created **lazily** through a `sb()` getter on first use, never at script top level |
| Hosting | Cloudflare Pages, static, **no build step**, output directory `public` |
| Config | `public/config.js` sets `window.APP_CONFIG` (public values only) |

**Plan note (★1):** check Supabase's current free-tier terms at setup. Historically, free projects pause after a period of inactivity and do not include automated backups. For a test deployment that may sit idle between client sessions, record the chosen plan and its pause and backup behavior in `HANDOVER.md` §8.

---

## 4. Information architecture (unchanged)

- **Model:** existing single-page app; `switchView()` swaps the content area. No routes added.
- **Entry:** login overlay (username + password, same as today).
- **Views (all preserved, same order, same labels):** Division Summary View · District Profile View · Termly Comparative Analysis · Performance Dashboard · Fast Data Entry & Upload · Least Learned Competencies · Grade Level Breakdown · Reports & Signatories · Settings & Branding (Admin/Supervisor only).
- **Global filter bar, Print Report, Clear Filters:** preserved.
- **New UI elements allowed (polish only):** mobile nav toggle, toast notifications, loading indicator, re-authentication modal (replaces `prompt()`), test-environment banner. Nothing else.

---

## 5. File structure

```
public/                         # Cloudflare Pages output dir (no build step)
  index.html                    # the app (from mapehDavNor.html), edited in place
  config.js                     # window.APP_CONFIG: public values + reserved feature flags
  _headers                      # CSP + security headers (§8.6)
supabase/
  migrations/
    0001_schema.sql             # tables, types, indexes, triggers (§7)
    0002_rls.sql                # helper functions + policies (§8)
    0003_audit.sql              # audit_log + triggers (§11)
  seed/
    districts.sql               # 11 districts + current coordinator defaults (★5, ★6)
    settings.sql                # app_settings row from current defaults
    demo_records.sql            # optional, every row is_demo = true (★4)
  tests/
    rls_matrix.sql              # Appendix C checks, run as each role
legacy/
  mapehDavNor.original.html     # untouched original: regression baseline, never edited
fixtures/
  regression.json               # deterministic records + independently computed expected outputs
tools/
  legacy-export.html            # ONLY if ★7 confirms existing browser data (§9.8)
docs/
  AUDIT.md                      # code audit report (Appendix B is the starting register)
CLAUDE.md                       # this file
HANDOVER.md                     # produced at the end (Appendix A)
```

**Rule:** the app stays in one HTML file. The only new script includes are `config.js`, supabase-js, and the upgraded SheetJS.

---

## 6. Brand system (LOCKED: existing tokens, do NOT invent)

```
--deped-blue:   #0038A8
--deped-dark:   #002266
--deped-yellow: #FCD116
--bg-body:      #F4F6F9
--success:      #2F855A   --warning: #DD6B20   --danger: #E53E3E
```
- **Keep** the DepEd palette, sidebar identity, badge colors, the Excel-style comparative table, and the print header and footer design.
- **Type:** replace the single `'Segoe UI'` family (missing on Android and macOS) with a system stack that **starts** with Segoe UI: `'Segoe UI', system-ui, -apple-system, Roboto, 'Helvetica Neue', Arial, sans-serif`. Print header fonts are unchanged.
- **Polish means consistency, not redesign:** one spacing scale, one button size set, visible focus rings, consistent disabled states, consistent card headers. No new color families, no animations beyond 150ms state transitions.
- **`@media print` block: do not edit.** Print output must match the original (verified in §14 M5).

---

## 7. Configuration and data: single source of truth

**Config.** `public/config.js` is the only place for environment values:

```js
window.APP_CONFIG = {
  environment: "test",                         // "test" shows the banner (§12); "production" hides it
  supabaseUrl: "https://[PROJECT-REF].supabase.co",
  supabasePublishableKey: "[PUBLISHABLE_KEY]", // public by design; security comes from RLS
  authEmailDomain: "users.mapehdavnor.altasme.app",
  supabaseJsVersion: "2.x.y",                  // pinned at build time, recorded in HANDOVER
  features: {                                  // RESERVED upgrade seams (§16). Do not wire.
    recordEditing: false,
    excelDataExport: false,
    importValidation: false,
    duplicateDetection: false,
    selfServicePassword: false
  }
};
```

The existing constants block in `index.html` (`SUBJECTS`, `SPS_OFFERS`, `SPFL_OFFERS`, `IPED_OFFERS`, `KEY_STAGES`, `ALL_GRADES`, `SCHOOL_YEARS`) stays where it is and is unchanged. `DEFAULT_DISTRICTS` becomes `let` and is filled from the `districts` table after login (same names, same order via `sort_order`).

**Schema (mirror of today's data, nothing more).** Snake_case in the database, camelCase in the app via a single mapper pair `fromRow()` / `toRow()` so every renderer keeps reading `r.mps`, `r.learningArea`, `r.district`, and so on.

```sql
create type public.app_role as enum ('admin', 'supervisor', 'district_coordinator');

create table public.districts (
  id smallint generated always as identity primary key,
  name text not null unique,
  coordinator_name text not null default '',
  coordinator_position text not null default '',
  sort_order smallint not null
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  display_name text not null,
  role public.app_role not null,
  district_id smallint references public.districts(id),
  constraint coordinator_needs_district
    check (role <> 'district_coordinator' or district_id is not null)
);

create table public.assessment_records (
  id bigint generated always as identity primary key,
  sy text not null check (sy ~ '^[0-9]{4}-[0-9]{4}$'),
  term text not null check (term in ('Term 1', 'Term 2', 'Term 3')),
  district_id smallint not null references public.districts(id),
  school text not null default '',
  key_stage text not null,
  grade_level text not null,
  learning_area text not null,
  baseline_mps numeric(5,2) not null check (baseline_mps between 0 and 100),
  mps numeric(5,2) not null check (mps between 0 and 100),
  pct75 numeric(5,2) not null check (pct75 between 0 and 100),
  proficiency_level text not null,            -- still computed client-side by getPL(), as today
  least_learned jsonb not null default '[]',  -- same [{code, desc}] shape as today
  is_demo boolean not null default false,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.assessment_records (district_id, sy, term);
create index on public.assessment_records (learning_area);

create table public.comparative_notes (     -- replaces localStorage comp_notes_* keys
  id bigint generated always as identity primary key,
  sy text not null,              -- 'ALL' allowed, mirrors the legacy key exactly
  district_scope text not null,  -- district name or 'ALL'
  subject text not null,         -- 'ALL' allowed
  term text not null,            -- 'ALL' allowed
  analysis text not null default '',
  interventions text not null default '',
  updated_by uuid not null default auth.uid(),
  updated_at timestamptz not null default now(),
  unique (sy, district_scope, subject, term)
);

create table public.app_settings (          -- replaces localStorage deped_easy_settings_v4
  id smallint primary key default 1 check (id = 1),
  data jsonb not null,           -- same keys as today's settings object, logos as data URLs
  updated_by uuid default auth.uid(),
  updated_at timestamptz not null default now()
);
```

Triggers in `0001`: `updated_at` touch on update for all tables; `created_by := auth.uid()` forced on insert into `assessment_records` (the client cannot spoof it).

**Not added (deliberately):** no unique constraint on assessment records (would change today's behavior, see §16), no check constraints on grade/subject/key-stage text, no normalized competency table.

---

## 8. Authentication and access control (replaces the house CTA section)

### 8.1 Login (same screen, same fields)
- User types a **username** and password. App calls `signInWithPassword({ email: \`${username.toLowerCase()}@${APP_CONFIG.authEmailDomain}\`, password })`. If ★3 resolves to real emails, accept input containing `@` as-is.
- After sign-in, load `profiles` joined to `districts` and build the same `currentUser` object the app uses today: `{ name, role, username, district }`, where role maps `admin → "Admin"`, `supervisor → "Supervisor"`, `district_coordinator → "District Coordinator"` and district is the district name or `"ALL"`.
- **Delete** `USER_ACCOUNTS` and every read or write of `sessionStorage.deped_current_user`. The session comes only from supabase-js.
- On load: `getSession()`; if present, load the profile and continue; if not, show the login overlay. Subscribe to `onAuthStateChange`; on `SIGNED_OUT`, show the overlay.
- Logout: `signOut()` then `location.reload()` (also clears stale filter state).
- Supabase Auth settings: **public sign-ups disabled**, email confirmation off (admin-created users), Site URL and redirect URL set to the Pages URL.

### 8.2 Helper functions (`0002_rls.sql`)
Do **not** name a function `current_role`, which is a reserved SQL keyword.

```sql
create or replace function public.app_role_of_user() returns public.app_role
language sql stable security definer set search_path = '' as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.app_district_of_user() returns smallint
language sql stable security definer set search_path = '' as $$
  select district_id from public.profiles where id = auth.uid()
$$;

create or replace function public.app_is_division_user() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.app_role_of_user() in ('admin', 'supervisor'), false)
$$;
```

### 8.3 Policies
RLS **enabled on every table**. `revoke all on all tables in schema public from anon;`

| Table | select | insert | update | delete |
|---|---|---|---|---|
| `assessment_records` | division user, or own district | division user, or own district (with check) | same (using + with check: a coordinator cannot move a record to another district) | division user only |
| `comparative_notes` | division user, or `district_scope` = own district name | same | same | none |
| `districts` | any authenticated | none | division user | none |
| `app_settings` | any authenticated (every user prints) | none | division user | none |
| `profiles` | own row only | none | none | none |
| `audit_log` | admin only | none (trigger only) | none | none |

This preserves today's permissions exactly: all signed-in users can enter data in their scope; only Admin/Supervisor can open Settings, edit coordinators, and bulk delete. The difference is that the **database** now enforces it.

### 8.4 Account provisioning (no UI; documented in HANDOVER §7)
1. For each row in **Appendix D**: Supabase Dashboard → Authentication → Add user (auto-confirm), email `username@users.mapehdavnor.altasme.app`, password **exactly as defined for that username in `legacy/mapehDavNor.original.html`** (`USER_ACCOUNTS`). Copy it from that file at provisioning time; do not retype it into any other file.
2. `insert into public.profiles (id, username, display_name, role, district_id) values (...)` using the Appendix D values verbatim, `district_id` looked up from `districts.name`.
3. Passwords are not copied into this spec, `HANDOVER.md`, `config.js`, seeds, or migrations. The only repo copy is the untouched original in `legacy/`, which sits outside `public/` and is never deployed. The repo stays private. Users already know their passwords; nothing new is distributed.
4. Verify all 13 logins from the deployed URL before handover.

### 8.5 Destructive actions
- Remove the hardcoded password check (the literal is in `legacy/` only) and the `prompt()` (which shows the password in clear text).
- Replace with a **re-authentication modal**: a password field (`type="password"`) that calls `signInWithPassword` with the current user's own email. On success, show the existing confirm text, then delete.
- Delete by SY: `.delete().eq('sy', sy)`. Clear all: `.delete().gt('id', 0)` (supabase-js refuses an unfiltered delete). Report the deleted count from the response.

### 8.6 `public/_headers`
```
/*
  Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://cdn.sheetjs.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self' https://[PROJECT-REF].supabase.co; font-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: camera=(), microphone=(), geolocation=()
```
`'unsafe-inline'` on scripts is required because the app uses inline `onclick` handlers (kept as is). Record this in `AUDIT.md` as an accepted residual risk; output escaping (§9.5) is the real XSS control.

---

## 9. Module-by-module changes

### 9.1 Data layer swap (the only structural change)
Replace the bodies of the IndexedDB helpers; keep their names and return shapes so renderers stay untouched.

| Existing function | New behavior |
|---|---|
| `initDB()` | No IndexedDB. Loads `districts` and `app_settings` into `DEFAULT_DISTRICTS`, `districtCoordinators`, `settings` after login. **No demo seeding** |
| `getAllRecords()` | Paginated select ordered by `id`, `.range()` in pages of 1000 until a short page returns. **PostgREST caps responses at 1000 rows by default; without pagination, averages are silently wrong.** Map rows with `fromRow()`, coercing numerics with `Number()` |
| `addRecord(r)` | `insert(toRow(r)).select('id')`; throw on `error` |
| `bulkInsert(rs)` | One `insert([...])` call (a single statement, so all-or-nothing); throw on `error` |
| `deleteRecordsBySY`, `clearDatabase` | §8.5 |
| `updateBaselineMpsForStage` | One `update({ baseline_mps })` with the same filters as today (`sy`, effective district, subject, term, `grade_level in ks.grades`). **Before** updating, run a `count: 'exact', head: true` query with the same filters and confirm: "This will change the baseline on N records." (today it silently rewrites every matching record) |
| `saveComparativeNotes(key)` | `upsert` into `comparative_notes` on `(sy, district_scope, subject, term)`, parsed from the same filter values the legacy key used |
| Notes reads in `renderComparativeView` | Select from `comparative_notes` (one query for the scope, one for all districts when scope is `ALL`) |
| `saveSettings`, `savePrintBrandingSettings` | Update `app_settings.data` (merge the same keys). Logo uploads capped at 500 KB each with a clear message |
| `saveDistrictCoordinators` | Update `districts` rows |

Every write: `await`, check `error`, show a success toast **only** on a confirmed response, otherwise an error toast with a readable message (§9.4). Disable the submit button while the request is in flight.

### 9.2 District mapping
`fromRow()` maps `district_id → name`; `toRow()` maps `name → id`. An Excel row whose district name is not in the table is **rejected before insert** with the row number and the bad value listed (today it becomes "Unassigned", which no longer exists as a valid district).

### 9.3 Excel import (kept as is, except what the database now refuses)
- Keep all column-name fallbacks and least-learned parsing exactly as they are.
- Keep today's silent defaults (grade "Grade 1", subject "MAPEH - Music & Arts", term "Term 1", missing MPS = 0, baseline = 65). They are documented as AUDIT M1 and fixed only in the upgrade.
- The database constraints now reject what is impossible: SY not in `YYYY-YYYY` form, MPS/baseline/% outside 0-100, unknown district. Because the insert is one statement, **a single bad row rejects the whole file**: show which constraint failed and nothing is saved.
- Remove the dead `reader.readAsBuffer ?` branch; use `readAsArrayBuffer`.
- Template download (`downloadExcelTemplate`): unchanged.

### 9.4 Error messages
Map Postgres constraint names and codes to plain English in one function: check-constraint failures ("MPS must be between 0 and 100"), FK failures ("Unknown district"), RLS denials (`42501`: "You do not have access to that district's data"), network errors ("Could not reach the server. Your changes were not saved.").

### 9.5 Output escaping (XSS fix)
Add `esc(s)` (escapes `& < > " '`) and apply it to **every** stored or imported string interpolated into `innerHTML` or an attribute: school, learning area, competency code and description, notes (including inside `<textarea>`, where `</textarea>` would otherwise break out), coordinator name and position, settings values in `value="..."`, district names, SY strings. Numbers formatted with `toFixed()` do not need escaping. Search for every `${` in a template that builds HTML and justify each unescaped one in a code comment.

### 9.6 Empty states (display only; formulas untouched)
When a group has zero records, show "No data" (muted) instead of `0.00%` with a "Beginning" badge, and in the comparative table show `-` for variance and status instead of `-65.00% Decreased`. The underlying computation is unchanged; only the zero-count branch renders differently.

### 9.7 Unsaved changes
Track a dirty flag on the comparative notes textareas and the manual entry form. Guard `switchView`, `applyFilters`, logout, and `beforeunload` with a confirm when dirty.

### 9.8 Legacy export tool (ONLY if ★7 confirms existing data)
A standalone `tools/legacy-export.html` that opens the old IndexedDB (`DepEdDivisionDB_v21_ClearSYSupport`) and the localStorage keys on the coordinator's own browser and downloads JSON. Records that match the demo seed patterns (generated school names such as "`<District> National High School (SPA Campus)`" and LC codes like `MAPE-Grade1-LC1`) are excluded and counted separately. Import into Supabase is done by Altaventures after a count and spot-check with the client.

---

## 10. Excel and reports

- Import: §9.3. Template download: unchanged. Print: unchanged (§6).
- **There is no Excel data export in the current app** (only the template). The original brief asked to "preserve" it; it cannot be preserved because it does not exist. It is listed in the upgrade map (§16).

---

## 11. Analytics: none · Audit log instead

No Meta Pixel, no analytics, no third-party tracking. This is an internal government tool.

`0003_audit.sql`: `audit_log (id, at timestamptz, actor uuid, table_name, action, row_id, old jsonb, new jsonb)` filled by `security definer` triggers on insert/update/delete of `assessment_records`, `comparative_notes`, `districts`, `app_settings`. Readable by Admin only through the Supabase dashboard (no UI).

---

## 12. Data-integrity rules (HARD CONSTRAINTS)

1. **Demo data is always flagged** (`is_demo = true`) and never mixed silently with real data.
2. **Test-environment banner.** When `APP_CONFIG.environment === "test"` or any `is_demo` row exists, show a persistent non-printing banner: "Test environment: figures may include sample data." It is hidden in `@media print` **only** when no demo rows are in the current filter. Otherwise the printed report carries a "SAMPLE DATA" line under the title.
3. **No save is reported without a database confirmation.**
4. **No privileged secret in the frontend or repo.** Only the publishable key ships. The service-role key is never committed or pasted into chat.
5. **No calculation changes** (§0.3). Any deviation found during regression is a bug in the port, not a fix.

---

## 13. Responsive and performance

- **Sidebar:** fixed at 1024px and above; below that it becomes an off-canvas drawer opened from a header button, main content full-width.
- **Header:** the long system title wraps cleanly; the user badge stays reachable at 360px.
- **Filter bar:** wraps; selects go full-width under 640px.
- **Tables:** wrap every `.data-table` and `.excel-table` in a horizontal scroll container. No page-level horizontal scroll at 360px.
- **Charts:** `.chart-grid` uses `minmax(min(400px, 100%), 1fr)` (today's 400px minimum overflows phones).
- **Nav items:** add `role="button"`, `tabindex="0"`, and Enter/Space handling (keyboard access).
- **Loading:** show a loading state in the content area while a view's data loads; never render a view from half-loaded data.
- **Data volume:** views refetch on switch, as today (refresh-to-update is acceptable per the brief). Acceptable at test volumes; noted in HANDOVER §9.

---

## 14. Build sequence (milestones)

- **M0 Audit (no code changes):** copy the original to `legacy/` untouched. Write `docs/AUDIT.md` from Appendix B, verifying each finding against the code. Build `fixtures/regression.json` (hand-chosen values, expected outputs computed by hand or spreadsheet, not by the app).
- **M1 Supabase:** create project (Singapore), run migrations, seeds, auth settings, provision accounts (★2/★3). Run `supabase/tests/rls_matrix.sql` (Appendix C) and record results.
- **M2 Data layer:** §8.1 and §9.1 to §9.4. Remove `USER_ACCOUNTS`, `seedDemoData` runtime call, sessionStorage trust, hardcoded delete password.
- **M3 Security fixes:** §9.5 escaping, SheetJS upgrade, supabase-js pinned with SRI, `_headers`.
- **M4 Visual polish:** §6, §9.6, §9.7, §13, toasts, re-auth modal, banner. Print CSS untouched.
- **M5 QA + deploy:** regression (load `fixtures/regression.json` into the legacy file and into Supabase; every number on every view must match), RLS matrix from the browser as each role, print comparison (same filters, PDF side by side), 360px pass, Cloudflare Pages deploy, smoke test, **produce `HANDOVER.md`**.

---

## 15. Definition of done

- All 9 views render and behave as in the original; regression fixture matches on every view.
- No credentials, passwords, or service-role key anywhere in `public/` or git history.
- RLS matrix (Appendix C) passes for every role; denial verified from the browser, not only SQL.
- Every save path shows success only on confirmed writes and a readable error on failure.
- Every stored string rendered through `esc()`.
- Print output matches the original for division and district scope.
- Usable at 360px with no page-level horizontal scroll.
- `docs/AUDIT.md` complete with every finding's disposition.
- **`HANDOVER.md` exists and is complete (Appendix A).**

---

## 16. Explicitly OUT of scope: upgrade activation map

The client will request expansion when ready. Seams are reserved in `APP_CONFIG.features` (§7). **Reserve, don't wire.** Building any of these now is scope creep.

| Flag | Now | Turns on | Client inputs needed |
|---|---|---|---|
| `recordEditing` | `false` | Edit and delete individual records (today only bulk delete by SY or all) | Who may edit what, after which deadline |
| `excelDataExport` | `false` | Export filtered, authorized records to .xlsx | Required column layout |
| `importValidation` | `false` | Row-level validation report, no silent defaults, partial accept | Rules for missing fields |
| `duplicateDetection` | `false` | Reject or update on re-import | Agreed record identity (SY + term + district + school + grade + subject?) |
| `selfServicePassword` | `false` | Change-password and reset-by-email flows | Real emails (★3) |
| (new) | n/a | Weighted MPS by learner count, competency code standard, school master list, realtime refresh, user management UI, offline use, production hardening and backups | Methodology confirmation (★10), budget |

---

## 17. Working rules for the build assistant (Claude Code or equivalent)

- **Minimal diffs.** Edit the existing file in place. Keep function names, globals, and markup structure unless this spec says otherwise.
- **No framework, no bundler, no file split** beyond `config.js`.
- **Never change a formula.** If regression differs, the port is wrong.
- Supabase client is **lazy** through `sb()`; never created at script top level.
- Never commit or print the service-role key, database password, or user passwords.
- When something looks like a feature gap, add it to `AUDIT.md` and §16, don't build it.
- When client docs conflict with this file, **this file wins**: note it, proceed.
- No em dashes or en dashes in any deliverable.
- **On completion, always produce `HANDOVER.md`** using Appendix A.

---

## 18. Mandatory deliverable: the handover file

At the end of the build, generate `HANDOVER.md` at the repo root from **Appendix A**. Two readers: (a) Altaventures and the client at the test handover, (b) whoever builds the upgrade later. No handover = build incomplete.

---

# APPENDIX A: `HANDOVER.md` TEMPLATE

> _Copy this block to `HANDOVER.md` at the repo root and fill every field. Write "n/a" only if truly not applicable._

```markdown
# HANDOVER: MAPEH Davao del Norte Assessment System · Test Deployment

**Built by:** Altaventures Business Development Services
**Handover date:** [YYYY-MM-DD]  ·  **Spec version built:** [vN]
**Test URL:** [https://....pages.dev]  ·  **Repo:** [github url]

## 1. What was delivered
- Existing app online on Cloudflare Pages, all 9 views preserved.
- Shared Supabase database replacing per-browser storage.
- Supabase login replacing hardcoded accounts; district access enforced in the database.
- Code audit: docs/AUDIT.md ([N] findings: [n] fixed, [n] documented for upgrade).
- Visual polish: responsive layout, loading / empty / error states, toasts.
- [Anything shipped as a placeholder and why.]

## 2. Run & deploy
- No build step. Cloudflare Pages: framework preset None, build command empty, output dir `public`.
- Deploys on push to [branch].
- Config: public/config.js (public values only). Pinned versions: supabase-js [x], SheetJS [x], Chart.js 4.4.1.
- Database changes: supabase/migrations, applied in order.

## 3. Where to edit
- Signatories, header and footer text, logos, coordinator names: Settings & Branding (Admin/Supervisor), no developer needed.
- Subjects, grades, key stages, school years: constants block in public/index.html (developer).
- Districts list: `districts` table (developer).

## 4. Upgrade activation map
[Copy the §16 table with current status of each flag.]

## 5. Outstanding blocking inputs
- [★N: still unresolved, currently: default X]

## 6. Data-integrity status
- [ ] Demo rows present: [count]. Purge: `delete from public.assessment_records where is_demo;`
- [ ] Test banner on / off
- [ ] Coordinator names and signatories replaced with real values
- [ ] Real data: not applicable (prototype, ★4). Real data requires an upgrade plus SDO authorization

## 7. Account administration
- Create a user: Supabase Dashboard > Authentication > Add user (auto-confirm), then insert the profiles row: [SQL snippet].
- Reset a password: Dashboard > Authentication > user > [steps].
- Disable a user: [steps].
- Current accounts: [count by role]. Passwords delivered privately on [date].

## 8. Accounts & infrastructure (pointers, NOT secrets)
- Cloudflare Pages: [account owner] / [project name]
- Supabase: Altaventures dedicated account / [project ref] / region ap-southeast-1 / plan [x]
- Inactivity pause behavior: [x]. Backups: [automated / manual export schedule / none]
- Repo: [url]

## 9. Known limitations
- No record editing or single-record delete; no Excel data export.
- Import applies silent defaults; one bad row rejects the whole file; no duplicate detection.
- Division MPS differs between Division Summary and Dashboard (different averaging, AUDIT M3).
- Inline script handlers require 'unsafe-inline' in CSP (AUDIT, accepted).
- [Others.]

## 10. Recommended next steps
- [Plain-language points for the client: what the upgrade unlocks, what they must decide first.]
```

---

# APPENDIX B: Audit findings register (starting point for `docs/AUDIT.md`)

_Verify each against the code in M0. Disposition: **FIX** (this engagement) or **DOC** (documented, upgrade)._

| ID | Severity | Finding | Disposition |
|---|---|---|---|
| C1 | Critical | 13 usernames and passwords, including Admin, hardcoded in page source | FIX: Supabase Auth (§8.1) |
| C2 | Critical | Logged-in user trusted from editable sessionStorage; anyone can become Admin | FIX: profile from DB + RLS (§8) |
| C3 | Critical | Destructive-action password hardcoded (same as Admin's) and typed into cleartext `prompt()` | FIX: re-auth modal (§8.5) |
| C4 | Critical | Stored XSS: imported and entered text rendered via `innerHTML` unescaped; becomes cross-user once shared | FIX: `esc()` (§9.5) |
| C5 | Critical | Demo data (about 1,452 random records) auto-seeded into SY 2025-2026 on first load, unflagged | FIX: removed from runtime; flagged optional seed (§12) |
| H1 | High | SheetJS 0.18.5 has known vulnerabilities when parsing crafted files | FIX: upgrade (§3) |
| H2 | High | IndexedDB writes have no error handling; failures hang or report success | FIX: confirmed writes (§9.1) |
| H3 | High | Editing a baseline silently overwrites `baselineMps` on every matching record | FIX: count + confirm (§9.1). Behavior otherwise preserved |
| H4 | High | (Introduced by migration) PostgREST 1,000-row default cap would truncate averages | FIX: pagination (§9.1) |
| H5 | High | CDN scripts unpinned for integrity (no SRI) | FIX: pin + SRI (§3) |
| M1 | Medium | Import silently defaults missing grade, subject, term, MPS (0), baseline (65) | DOC (upgrade: `importValidation`) |
| M2 | Medium | No duplicate detection; re-importing a file doubles the data | DOC (upgrade: `duplicateDetection`) |
| M3 | Medium | "Division MPS" computed three ways: mean of district means of term means (Division Summary) vs flat mean (Dashboard, District Profile) | DOC, client to confirm methodology (★10) |
| M4 | Medium | All MPS aggregates are unweighted means of record MPS; no learner counts stored | DOC (★10) |
| M5 | Medium | Proficiency scale (90/85/80/75) should be confirmed as the official scale for these assessments | DOC (★10) |
| M6 | Medium | Least-learned ranking groups exact free-text matches; near-duplicates never merge | DOC |
| M7 | Medium | Mixed record grain: MAPEH district-level (no school), special programs school-level, averaged together | DOC |
| M8 | Medium | Key stage not validated against grade; Key Stage filter uses `keyStage` while comparative uses grade membership | DOC |
| M9 | Medium | No record editing, single-record delete, or data export (original brief assumed these existed) | DOC (upgrade) |
| M10 | Medium | Supervisor has full Admin powers (settings, bulk delete) | DOC, client to confirm (★8) |
| L1 | Low | Empty groups show "0.00% Beginning"; empty key stages show "-65.00% Decreased" | FIX: display only (§9.6) |
| L2 | Low | Logout leaves filter state from the previous user | FIX: reload on sign-out (§8.1) |
| L3 | Low | Dead `readAsBuffer` branch | FIX: cleanup (§9.3) |
| L4 | Low | Default coordinator and signatory names look like placeholders and print on reports | DOC + banner (★5) |
| L5 | Low | School years start at 2025-2026; prior-SY baselines cannot be entered as records | DOC |
| L6 | Low | Nav items not keyboard accessible | FIX (§13) |
| L7 | Low | Logos stored as base64 in settings (size risk) | FIX: 500 KB cap (§9.1) |
| R1 | Accepted | CSP needs `'unsafe-inline'` for scripts because inline handlers are kept | Accepted residual risk (§8.6) |
| R2 | Accepted | Original passwords kept by client direction; they appear in the client's original file, so anyone with that file can sign in as any account, including Admin | Accepted for the prototype. Removed from deployed source (C1). Recommend new passwords before any real data goes in (upgrade) |

---

# APPENDIX C: RLS test matrix (`supabase/tests/rls_matrix.sql` + browser check)

Run each as a real signed-in user (SQL: `set local role authenticated; set local request.jwt.claims = '{"sub":"<uuid>"}';`).

| Action | Admin | Supervisor | Coordinator (own district) | Coordinator (other district) | Signed out |
|---|---|---|---|---|---|
| Read records | all | all | own only | 0 rows | denied |
| Insert record | any district | any district | own | denied | denied |
| Update record district to another | allowed | allowed | denied | denied | denied |
| Delete records | allowed | allowed | denied | denied | denied |
| Read / write notes for own scope | yes | yes | yes | no | no |
| Update settings / districts | yes | yes | denied | denied | denied |
| Read profiles | own | own | own | own | denied |
| Change own role | denied | denied | denied | denied | denied |
| Read audit_log | yes | denied | denied | denied | denied |

---

# APPENDIX D: Accounts to provision (★2, ★3 resolved)

_Verbatim from `USER_ACCOUNTS` in the original code. Each account keeps its original password (v1.2), set from `legacy/mapehDavNor.original.html` at provisioning. Passwords are deliberately not repeated here (§8.4)._

| # | Username | Display name | Role | District |
|---|----------|--------------|------|----------|
| 1 | `admin` | System Administrator | `admin` | (none: division) |
| 2 | `supervisor` | Education Program Supervisor | `supervisor` | (none: division) |
| 3 | `asuncion_coord` | Asuncion District Coordinator | `district_coordinator` | Asuncion |
| 4 | `dujali_coord` | B.E. Dujali District Coordinator | `district_coordinator` | B.E. Dujali |
| 5 | `carmen_coord` | Carmen District Coordinator | `district_coordinator` | Carmen |
| 6 | `kapalonge_coord` | Kapalong East District Coordinator | `district_coordinator` | Kapalong East |
| 7 | `kapalongw_coord` | Kapalong West District Coordinator | `district_coordinator` | Kapalong West |
| 8 | `newcorella_coord` | New Corella District Coordinator | `district_coordinator` | New Corella |
| 9 | `sanisidro_coord` | San Isidro District Coordinator | `district_coordinator` | San Isidro |
| 10 | `stotomase_coord` | Sto. Tomas East District Coordinator | `district_coordinator` | Sto. Tomas East |
| 11 | `stotomasw_coord` | Sto. Tomas West District Coordinator | `district_coordinator` | Sto. Tomas West |
| 12 | `talaingod_coord` | Talaingod District Coordinator | `district_coordinator` | Talaingod |
| 13 | `langilan_coord` | Langilan District Coordinator | `district_coordinator` | Langilan |

Login lowercases the typed username before mapping, matching today's case-insensitive username check.
