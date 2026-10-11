# MAPEH Davao del Norte Assessment System (test deployment)

Single-file web app (`public/index.html`) backed by Supabase, hosted on Cloudflare Pages with no build step.
`CLAUDE.md` is the build spec, `docs/AUDIT.md` the audit, `HANDOVER.md` the handover.

- `legacy/mapehDavNor.original.html` is the client's original, untouched.
- `supabase/migrations` then `supabase/seed` set up the database. `supabase/tests/rls_matrix.sql` checks access rules.
- `tools/provision-accounts.mjs` creates the 13 accounts. `tools/gen_demo_records.py` regenerates the sample data.
- `tools/load-demo-records.mjs` loads the sample rows. `tools/verify-live.mjs` and `tools/qa/live_smoke.mjs` test the live project.
- `tools/qa/run_qa.mjs` runs the original and the port side by side. `tools/verify-sri.sh` checks the pinned scripts.

No secret belongs in this repository. Only the Supabase publishable key goes in `public/config.js`.
