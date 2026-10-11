# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users
District assessment coordinators (11 districts of Davao del Norte) who enter and review MAPEH, SPA, SPS, SPFL and IPED assessment results for their own district, and Division office staff (Education Program Supervisor, administrators) who consolidate all districts, review trends, edit signatories and print the official report. Used mainly at office desks on laptops and desktops with wide tables; phones are secondary but must work.

## Product Purpose
Consolidate per-district assessment results (Mean Percentage Scores, proficiency levels, least learned competencies) into division-level views and an official printed report for the Schools Division Office. Success: a coordinator enters or uploads a district's data in minutes, and the Division can read performance by district, term, key stage and program, and print a report without rebuilding it in Excel.

## Positioning
An internal government assessment tool for SDO Davao del Norte, built around DepEd's own structures: districts, key stages, terms, the 90/85/80/75 proficiency scale and special programs (SPA, SPS, SPFL, IPED). Not a generic analytics dashboard.

## Operating Context
Government office and school-district setting. Data arrives by Excel template upload or manual entry per term. The printed report (letterhead, comparative table, signatories, footer with logos and contact details) is submitted to the Schools Division Office. Prototype phase: the deployment shows sample data and a test-environment banner.

## Capabilities and Constraints
Nine views, kept as is: Division Summary, District Profile, Termly Comparative Analysis, Performance Dashboard, Fast Data Entry & Upload, Least Learned Competencies, Grade Level Breakdown, Reports & Signatories, Settings & Branding (Admin/Supervisor only). Single static HTML file (public/index.html), vanilla JS, no build step, Supabase backend, Cloudflare Pages. All calculations, labels and workflows are unchanged by design work; only presentation changes. The printed report layout (the @media print block) must stay identical. Existing functions, element ids and inline handlers are relied on by logic and automated tests.

## Brand Commitments
Keep the DepEd identity: blue (#0038A8 / #002266) as the institutional anchor and yellow (#FCD116) as the accent, refined rather than replaced. Official names and header text come from Settings. No fabricated logos or seals.

## Evidence on Hand
Sample data only (1,452 flagged demo records). No client-supplied logos or photography exist yet; print shows no logo until uploaded. Do not invent testimonials, statistics or branding assets.

## Product Principles
- Numbers first: a coordinator should see the figure, its proficiency level and its comparison before any decoration.
- Official before expressive: it is a records tool for a public institution; clarity, restraint and trust outrank flair.
- Demo data is always visibly labelled and never presented as real.
- Presentation may change; calculations, labels, workflows and the printed report may not.
- Desktop tables are the primary working surface; phone use must remain complete.

## Accessibility & Inclusion
Keyboard operable navigation, visible focus, readable contrast on blue and yellow, no horizontal page scroll at 360px. Filipino and English users; text is English.
