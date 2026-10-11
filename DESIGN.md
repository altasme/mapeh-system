---
name: MAPEH Division Assessment Consolidation System
description: A DepEd report sheet on a tinted desk, where color means proficiency level and the ruler shows where a score sits.
colors:
  ultramarine: "#0038A8"
  ultramarine-hover: "#002f8f"
  navy: "#002266"
  blue-wash: "#eaf0fc"
  yellow: "#FCD116"
  ink: "#101b33"
  ink-2: "#3a4764"
  muted: "#56627e"
  faint: "#8592ad"
  desk: "#eceff5"
  sheet: "#ffffff"
  rule: "#dde3ee"
  rule-strong: "#bfc8da"
  notice-wash: "#fbf1c9"
  notice-ink: "#5a4400"
  level-advanced: "#17703f"
  level-proficient: "#1b56b0"
  level-approaching: "#765a00"
  level-developing: "#a14510"
  level-beginning: "#a3221a"
  band-beginning: "#f1cdc9"
  band-developing: "#f6d9bd"
  band-approaching: "#f2e5ac"
  band-proficient: "#c9dbf4"
  band-advanced: "#c6e5d2"
typography:
  display:
    fontFamily: "'Public Sans', 'Segoe UI', system-ui, -apple-system, Roboto, 'Helvetica Neue', Arial, sans-serif"
    fontSize: "2.35rem"
    fontWeight: 650
    lineHeight: 1.12
    letterSpacing: "-0.02em"
  headline:
    fontFamily: "'Public Sans', 'Segoe UI', system-ui, sans-serif"
    fontSize: "1.55rem"
    fontWeight: 650
    lineHeight: 1.2
    letterSpacing: "-0.02em"
  figure:
    fontFamily: "'Public Sans', 'Segoe UI', system-ui, sans-serif"
    fontSize: "2rem"
    fontWeight: 650
    lineHeight: 1.1
    letterSpacing: "-0.02em"
    fontFeature: "'tnum'"
  title:
    fontFamily: "'Public Sans', 'Segoe UI', system-ui, sans-serif"
    fontSize: "1.08rem"
    fontWeight: 650
    lineHeight: 1.5
    letterSpacing: "-0.005em"
  body:
    fontFamily: "'Public Sans', 'Segoe UI', system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
  table:
    fontFamily: "'Public Sans', 'Segoe UI', system-ui, sans-serif"
    fontSize: "0.88rem"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "'Public Sans', 'Segoe UI', system-ui, sans-serif"
    fontSize: "0.78rem"
    fontWeight: 600
    lineHeight: 1.5
    letterSpacing: "normal"
rounded:
  xs: "2px"
  sm: "6px"
  md: "8px"
spacing:
  xs: "6px"
  sm: "10px"
  md: "14px"
  lg: "24px"
  xl: "36px"
components:
  button-primary:
    backgroundColor: "{colors.ultramarine}"
    textColor: "{colors.sheet}"
    rounded: "{rounded.sm}"
    padding: "8px 14px"
  button-primary-hover:
    backgroundColor: "{colors.ultramarine-hover}"
  button-secondary:
    backgroundColor: "{colors.sheet}"
    textColor: "{colors.ink-2}"
    rounded: "{rounded.sm}"
    padding: "8px 14px"
  button-danger:
    backgroundColor: "{colors.sheet}"
    textColor: "{colors.level-beginning}"
    rounded: "{rounded.sm}"
    padding: "8px 14px"
  nav-item:
    textColor: "#cdd7ef"
    rounded: "{rounded.sm}"
    padding: "9px 12px"
  nav-item-active:
    backgroundColor: "rgba(255,255,255,0.13)"
    textColor: "{colors.sheet}"
  sheet:
    backgroundColor: "{colors.sheet}"
    rounded: "{rounded.md}"
    padding: "0 36px 40px"
  select-field:
    backgroundColor: "{colors.sheet}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    height: "36px"
    padding: "0 10px"
  text-input:
    backgroundColor: "{colors.sheet}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    height: "38px"
    padding: "0 12px"
  notice-banner:
    backgroundColor: "{colors.notice-wash}"
    textColor: "{colors.notice-ink}"
    padding: "7px 32px"
---

# Design System: MAPEH Division Assessment Consolidation System

## Overview

**Creative North Star: "The Report on the Desk"**

The screen shows each of the nine views as the official sheet it prints as. A cool, blue-tinted desk (#eceff5) holds one white sheet with a hairline border and a screen-only letterhead line that mirrors the printed header (division and region, report title, school year). What staff read is what the Division receives. Mode is Operate: a records tool for a public institution, where the figure, its proficiency level and its comparison come before any decoration.

The shell speaks DepEd: navy (#002266) rail and login panel, ultramarine (#0038A8) for actions and focus. Yellow (#FCD116) is a rare marker, used only on the active-nav tab and the short rule above the login heading. Everything else is quiet ink on white, separated by 1px hairlines rather than boxes. Color is reserved for meaning: the five proficiency bands. There are no colored-top KPI cards, no pill badges, no per-section rainbow, and no repeating uppercase titles.

Everything in this system is screen-only. The original `@media print` block is frozen so the printed report layout does not change. The legacy base CSS that precedes the redesign layer in `public/index.html` (uppercase titles, gradient login, colored-top cards) exists only to serve print and as the fallback beneath the redesign; new screens do not inherit its look.

**Key Characteristics:**
- Report-sheet-first: tinted desk, one white sheet, letterhead line, ruled sections inside it (no boxes in boxes).
- One family (Public Sans, self-hosted variable font) with tabular figures everywhere; sentence-case labels.
- Flat surfaces and 1px hairlines; the sheet alone gets a soft lift.
- Color means proficiency level and nothing else; the ruler is the signature.
- 150ms state transitions only.

## Colors

A navy-and-ultramarine institutional shell, a cool gray-blue desk, white paper, and a five-band proficiency scale that runs from clay through amber to green.

### Primary
- **DepEd Ultramarine** (#0038A8): primary buttons, links in context selects, active tab, focus ring and form accent. Hover deepens to #002f8f.
- **DepEd Navy** (#002266): sidebar rail, login brand panel, user avatar. The shell anchor.
- **Blue Wash** (#eaf0fc): hover on the upload dropzone and the editable baseline field fill.

### Secondary
- **DepEd Yellow** (#FCD116): the 4px active-nav marker on the rail and the 44px rule above the login heading. Nowhere else.

### Neutral
- **Ink** (#101b33): headings, figures, primary text.
- **Ink 2** (#3a4764): secondary buttons, form labels, table-header text on filled headers.
- **Muted** (#56627e): helper text, table column heads, filter labels.
- **Faint** (#8592ad): ruler tick numbers and the sheet-head organization line only.
- **Desk** (#eceff5): page background behind the sheet.
- **Sheet** (#ffffff): the report surface, inputs, selects.
- **Hairline** (#dde3ee) and **Hairline Strong** (#bfc8da): section dividers and row rules; control borders.
- **Notice Wash / Ink** (#fbf1c9 / #5a4400): the test-environment banner and the "sample data" chip, the only pale-yellow surface in the app.

### Proficiency Levels (DepEd scale: 90 / 85 / 80 / 75)
Each level has a text color for the level key and a tinted band for the ruler.
- **Advanced** (#17703f text, #c6e5d2 band): 90 and above.
- **Proficient** (#1b56b0, #c9dbf4): 85 to below 90.
- **Approaching Proficiency** (#765a00, #f2e5ac): 80 to below 85.
- **Developing** (#a14510, #f6d9bd): 75 to below 80.
- **Beginning** (#a3221a, #f1cdc9): below 75.

### Named Rules
**The Color Means Level Rule.** The five level colors appear only in the level key (a 9px square plus the level word), the ruler bands and the login scale legend. Never use them for decoration, section identity or status chrome. The word always accompanies the color.

**The Rare Yellow Rule.** Yellow marks the one place you are (active nav) and the login rule. It is never a fill, button or highlight on the sheet.

## Typography

**Display, Body and Label Font:** Public Sans (variable, weights 100 to 900, self-hosted `fonts/public-sans-latin-wght.woff2`, `font-display: swap`) with fallback `'Segoe UI', system-ui, -apple-system, Roboto, 'Helvetica Neue', Arial, sans-serif`.

**Character:** One civic grotesque at modest weights (400, 600, 650). Hierarchy comes from size and weight, not from case or a second face. Tabular figures are on at the body level so columns of MPS values align.

### Hierarchy
- **Display** (650, 2.35rem, 1.12): login brand heading only, tight tracking (-0.02em), max 15ch, balanced wrap.
- **Headline** (650, 1.55rem, 1.2): the view title on the desk (set from VIEW_TITLES), with a 0.85rem muted scope line under it.
- **Figure** (650, 2rem, 1.1): KPI values, including the division MPS.
- **Title** (650, 1.08rem): section headings inside the sheet.
- **Body** (400, 14px, 1.5): running text; tables at 0.88rem.
- **Label** (600, 0.76 to 0.82rem, sentence case, no tracking): filter labels, column heads, form labels, KPI titles, nav group names.

### Named Rules
**The Sentence-Case Rule.** Labels, column heads and nav groups are sentence case, not uppercase, with no letter-spacing.

**The Tabular Figures Rule.** Numbers are tabular and right-aligned in tables (`.num`); never mix in a second numeric face.

## Layout

A fixed 268px navy rail at 1024px and up, grouped into Overview, Records, Output and Admin with 18px line icons. Beside it, the desk: a header (view title and scope line left; Print Report as the primary button, user badge and Logout right), then a transparent filter strip of selects (36px high, wrapping, flex-end aligned), then the sheet.

The sheet is white, max-width 1280px, padding 0 36px 40px, 8px radius. It opens with the letterhead line (hairline underneath; organization at left, report title and school year), then content. Sections inside it are separated by a hairline and 28 to 36px of space, never nested in bordered boxes. KPIs form one ruled band: a 1px-gap grid (`auto-fit, minmax(210px, 1fr)`) inside a single 1px border. Charts sit in a grid with 40px gaps and 360px-high containers, unframed. Tables scroll horizontally inside their container; the page never scrolls sideways.

Spacing rhythm in use: 6, 10, 14, 24, 36px, with 12 to 20px between form rows. Below 1024px the rail becomes an off-canvas drawer opened from a Menu button, the filter strip collapses behind a Filters toggle, the sheet padding drops to 0 18px 28px, and the login splits to a single column (the scale legend and description hide). Below 640px forms go one column and buttons may wrap. Target: no page-level horizontal scroll at 360px.

## Elevation & Depth

Flat. Depth is conveyed by tone (navy rail, tinted desk, white sheet) and 1px hairlines, not shadows. The sheet alone has a soft lift (`0 1px 2px rgba(16,27,51,0.05), 0 12px 28px -18px rgba(16,27,51,0.22)`). The re-authentication modal (`0 20px 50px -20px rgba(16,27,51,0.5)`) and toasts (inherited legacy `0 4px 12px rgba(0,0,0,0.25)`) are the only other shadows, as overlays above the sheet.

### Named Rules
**The Flat Sheet Rule.** Nothing on the sheet casts a shadow. Rows, cards, KPIs and buttons separate with hairlines or tone.

## Shapes

Quietly squared: controls and buttons use a 6px radius, the sheet and KPI band 8px, level-key squares and ruler fills 2 to 3px. Borders are always 1px; the dropzone is the one dashed 1.5px border. Level keys are small squares, not pills.

## Components

### Buttons
- **Shape:** 6px radius, 600 weight, 0.86rem, padding 8px 14px (small: 5px 10px, 0.8rem); no wrap on desktop.
- **Primary:** ultramarine fill, white text; hover #002f8f. Print Report and the main action of a view.
- **Secondary:** white with a strong hairline, ink-2 text; hover #f1f4fa.
- **Danger:** white with a pale red border, Beginning-red text; hover #fbeceb.
- **Transitions:** background, border and color at 150ms ease. Focus is a 2px ultramarine outline with 2px offset.

### Navigation
Rail items are 0.875rem, 6px radius, 9px 12px padding, with an 18px stroke icon. Default text #cdd7ef; hover a white 8% wash; active a white 13% wash, white 600 text and the yellow 4px marker hugging the rail edge. Items are `role="button"` with tabindex; focus outline is yellow, inset. Group labels are 0.78rem sentence case in #8ea0cb.

### Sheet and letterhead
The white report surface (see Layout). Its screen-only letterhead line mirrors the print header text: a muted 0.78 to 0.82rem line with organization (faint), report title (600) and school year.

### KPI band
One ruled strip of cells, each with a muted 600 title, a 2rem figure, a 0.8rem sub-line and optionally a compact ruler. No colored top borders.

### Proficiency level key
A 9px rounded square in the level color plus the level word in 600 weight, inline. Replaces filled pills. Inside card headers the key is muted and loses its square.

### Proficiency ruler (signature)
A 6px track (4px compact, max 150px wide in cells, 120px in table cells) drawn from 60 to 100, split into the five level bands at the 75, 80, 85 and 90 cutoffs (37.5%, 50%, 62.5%, 75% of the track). A 4px-wide ink marker with a 2px white halo sits at the score's position, clamped to the track. The full size shows tick numbers (75, 80, 85, 90) in 0.66rem faint text; the compact size omits them. It is screen-only, carries `role="img"` with the value and level in its label, and draws the same value that classifies the level.

### Tables
Data tables: transparent header, muted 600 0.78rem column heads over a strong hairline, 10px 14px cells with hairline row rules, rows hover #f6f8fc, figures right-aligned. The Excel-style comparative table keeps its gridlines (hairline cells, #eef2fa header, #f4f7fd subject-total rows) inside a 6px-radius bordered container. Empty groups read "No data" in muted text.

### Inputs / Fields
White, 1px strong hairline, 6px radius; selects 36px, text inputs 38px (login 42px). Focus: 2px ultramarine outline plus ultramarine border. Disabled selects use #e8ecf4. The editable baseline field is blue-wash filled. File inputs use a styled bordered selector button. Notes textareas are 6px radius, 12px padding, line-height 1.55.

### Notice banner, toasts, modal
The test banner is a full-width pale-yellow strip (notice-wash, 0.8rem, 500) above the header, with a matching "sample data" chip beside headings when sample rows are in view. Toasts are 6px radius, white text on success green, danger red or ultramarine. The re-auth modal is a white 380px card over a 50% black scrim.

### Login
Two panels: navy brand panel at left (yellow rule, organization line, display heading, rating-scale legend using the five bands, footer) and a white form pane at right (360px column, left-aligned heading, 42px inputs, full-width primary button).

## Do's and Don'ts

### Do:
- **Do** treat each view as the sheet: tinted desk, white sheet, letterhead line, hairline-separated sections.
- **Do** show a level as the 9px square plus its word, and a score against the 60 to 100 ruler with cutoffs 75/80/85/90.
- **Do** keep figures tabular and right-aligned; keep labels sentence case.
- **Do** keep every redesign rule inside `@media screen` and leave the original `@media print` block untouched; mark any new screen-only element `.screen-only` so it is hidden in print.
- **Do** keep transitions at 150ms ease on color, background and border only.
- **Do** keep yellow to the active-nav marker and the login rule.

### Don't:
- **Don't** use level colors for anything but proficiency level (key, ruler bands, login legend).
- **Don't** reintroduce floating colored-top KPI cards, filled pill badges, per-section accent colors, or uppercase titles repeated per screen.
- **Don't** box a section inside a bordered, shadowed card inside the sheet.
- **Don't** add shadows on the sheet's contents, or animation beyond 150ms state transitions.
- **Don't** change a label, number or calculation for presentation reasons, and don't alter the printed report layout.
- **Don't** let the screen-only styling leak into print or inherit from the legacy base look.
