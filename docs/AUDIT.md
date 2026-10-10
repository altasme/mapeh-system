# AUDIT: MAPEH Davao del Norte Assessment System

Source audited: `legacy/mapehDavNor.original.html` (2,304 lines, unmodified).
Spec: `CLAUDE.md` v1.2, Appendix B is the starting register.
Status of this file: M0 verification complete. Dispositions marked FIX are applied in M2 to M4 and re-checked at M5.

Verification method: each finding was checked against the code (line numbers refer to the legacy file).

## Verified findings

| ID | Sev | Verified | Evidence (legacy file) | Disposition |
|----|-----|----------|------------------------|-------------|
| C1 | Critical | Yes | `USER_ACCOUNTS` lines 488-503: 13 accounts with plaintext passwords, including Admin. Matches Appendix D exactly (names, roles, districts) | FIX: Supabase Auth |
| C2 | Critical | Yes | Line 505 reads `currentUser` from `sessionStorage`; any user can edit it to role Admin, district ALL | FIX: profile from DB plus RLS |
| C3 | Critical | Yes | Lines 2254-2259 and 2269-2273: `prompt()` shows the typed password in clear text and compares to the literal `"depedmapehDavNor"`, which is also the Admin login password | FIX: re-auth modal |
| C4 | Critical | Yes | 206 `${` interpolations; stored and imported text (school, competency, notes, coordinator names, settings in `value="..."`) goes into `innerHTML` unescaped, e.g. lines 1061-1063 | FIX: `esc()` |
| C5 | Critical | Yes | `seedDemoData()` lines 661-711, called from `initDB()` line 655. 11 districts x 3 terms x 4 grades x 11 subjects = 1,452 records, unflagged, SY 2025-2026. Uses `Math.random()`, so the sample is not reproducible | FIX: removed at runtime; replaced by a deterministic, flagged `demo_records.sql` |
| H1 | High | Yes | Line 9: `xlsx@0.18.5` | FIX: upgrade |
| H2 | High | Yes | `addRecord`, `bulkInsert`, `deleteRecordsBySY`, `clearDatabase` (lines 723-766) have no `onerror` handlers; `getAllRecords` has none either; a failed transaction never resolves | FIX: confirmed writes |
| H3 | High | Yes | `updateBaselineMpsForStage` lines 768-800 rewrites `baselineMps` on all matching records with no confirmation | FIX: count plus confirm |
| H4 | High | Yes (migration risk) | PostgREST caps responses at 1,000 rows; the demo set alone is 1,452 | FIX: pagination |
| H5 | High | Yes | Lines 8-9: CDN scripts without SRI | FIX: pin plus SRI |
| M1 | Med | Yes | Import defaults (lines 1779-1851): term "Term 1", key stage "Key Stage 1", grade "Grade 1", subject "MAPEH - Music & Arts", MPS 0, baseline 65, pct75 0, district "Unassigned" | DOC |
| M2 | Med | Yes | No duplicate check in import | DOC |
| M3 | Med | Yes | Division Summary (lines 1047-1072): mean of district means of term means, and zero is treated as "no data". Dashboard (line 1453): flat mean of all records. Different results for the same filter | DOC (client confirms, star 10) |
| M4 | Med | Yes | No learner counts stored; all aggregates are unweighted means of record MPS | DOC |
| M5 | Med | Yes | `getPL` lines 803-809 uses 90/85/80/75 cutoffs | DOC (confirm official scale) |
| M6 | Med | Yes | Least-learned ranking groups by exact text | DOC |
| M7 | Med | Yes | MAPEH rows are district-level (no school); special programs are school-level; averaged together | DOC |
| M8 | Med | Yes | Global filter matches `r.keyStage` (line 837); comparative table matches by `ksObj.grades.includes(r.gradeLevel)` (line 791). A record with mismatched key stage and grade appears in one but not the other | DOC |
| M9 | Med | Yes | Only the template download exists; no record edit, single delete, or data export | DOC |
| M10 | Med | Yes | `canAccessSettings()` lines 508-510 treats Supervisor like Admin | DOC (star 8) |
| L1 | Low | Yes | Empty group renders `0.00%` with "Beginning" (line 1067) and the comparative table uses a baseline of 65 for empty key stages (line ~1241) giving "-65.00% Decreased" | FIX: display only |
| L2 | Low | Yes | `handleLogout` lines 541-547 does not reset `filters` | FIX: reload on sign-out |
| L3 | Low | Yes | Line 1860 `reader.readAsBuffer ? ...` is dead code (method does not exist) | FIX |
| L4 | Low | Yes | Placeholder-looking coordinator and signatory names, lines 611-634 | DOC plus banner (star 5) |
| L5 | Low | Yes | Line 564: school years run 2025-2026 to 2034-2035 | DOC |
| L6 | Low | To check in M4 | Nav items are not keyboard operable | FIX |
| L7 | Low | Yes | Logos stored as base64 in settings (lines 2138-2161) with no size cap | FIX: 500 KB cap |
| R1 | Accepted | n/a | CSP needs `'unsafe-inline'` for scripts (inline `onclick`) | Accepted |
| R2 | Accepted | n/a | Original passwords kept by client direction (v1.2). Anyone holding the original file can sign in as any account including Admin | Accepted for prototype; new passwords before real data |

## New findings from M0 (not in Appendix B)

| ID | Sev | Finding | Disposition |
|----|-----|---------|-------------|
| N1 | Low | Division Summary subtitle (line 1089) says "2 MAPEH, 7 SPA, 30 SPS, 10 SPFL & 8 IPED". `IPED_OFFERS` has 9 entries, so `SUBJECTS.length` is 58 while the text adds to 57. Copy is wrong | DOC (copy fix is a one-word change; apply only if the client agrees, since it changes displayed text) |
| N2 | Low | Zero MPS is treated as "no data" in Division Summary (`v > 0` filters, line 1053). A real term average of exactly 0 would be dropped. Unlikely in practice | DOC |
| N3 | Low | Import district fallback "Unassigned" is invalid after migration (district is a foreign key) | FIX per spec 9.2: reject row with row number and value |
| N4 | Info | `seedDemoData` creates the same school name for every grade of a district, so demo data is not a realistic school mix | DOC |

## Decisions recorded

- Formulas are not changed anywhere. The regression fixture (`fixtures/regression.json`) pins current behavior, including M3, so any port deviation shows up.
- Passwords exist only in `legacy/`, which is outside `public/` and never deployed. This file does not reproduce them.
