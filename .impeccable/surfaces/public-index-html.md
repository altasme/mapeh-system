---
version: 1
slug: "public-index-html"
primary_target: "public/index.html"
related_targets: []
---

# Surface brief: MAPEH assessment app (all nine views)

Scope and mode: Operate. Whole-app redesign inside the established DepEd identity (blue and yellow kept and refined). Desktop first, phone complete. Printed report layout is frozen: all new styling is screen-only.

Audience, job: district coordinators and Division staff enter, review and print assessment results. Constraints: single static HTML file, vanilla JS, ids and handlers unchanged, no numbers or labels changed.

Chosen direction and memorable moment: the screen is the report. The proficiency ruler, a 60 to 100 scale showing where a score sits against the 75, 80, 85 and 90 cutoffs.

## Direction contract

THESIS: The screen shows each view as the official sheet it prints as, on a tinted desk, so what staff read is what the Division receives. Refuses the generic dashboard: floating colored-top KPI cards, pill badges on every row, per-section rainbow colors, a long uppercase title repeating on every screen.

OWN-WORLD: DepEd ultramarine #0038A8 and navy #002266 carry the shell; the desk is a cool blue-tinted gray, the sheet is white with hairline rules. One family, Public Sans, tabular figures, sentence-case labels. Yellow #FCD116 appears only as the active-nav marker and the login rule. Color means proficiency: five tinted bands from clay through amber to green. Flat surfaces, 1px hairlines, no shadows except the sheet's soft lift.

STORY: Staff understand the division's standing in one glance, trust the numbers because they match the print, and act: scope, enter data, print.

FIRST VIEWPORT: 248px navy rail with grouped icon nav (Overview, Records, Output, Admin). On the desk: view title 22px and a one-line scope summary, Print as the primary button at right, then one compact scope strip of five selects. Below, the sheet: a letterhead line, the division MPS at 32px with its level and the proficiency ruler, then the district-by-term ledger with right-aligned figures and a ruler per district.

FORM: Report-sheet first, position 5 on the ordered list of 7, seed key b828ef9c.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
