/* EDITABLE CONTENT REGISTRY: the single list of text and images the /admin panel can change. Shared by the app (index.html)
   and the admin panel (admin/). Stable keys; the default text is what the page shows until an administrator saves a change.
   Anything not listed here is deliberately NOT editable from /admin (formulas, proficiency labels, role names, security and
   sample-data notices, database field names). Text is plain text; saved values are stored in public.site_content. */
window.SITE_REGISTRY = {
  schoolYears: Array.from({ length: 10 }, (_, i) => `${2025 + i}-${2026 + i}`),
  views: {   // screens an administrator may choose as the landing screen after sign-in
    "division": "Division Summary View", "dashboard": "Performance Dashboard", "district-view": "District Profile View",
    "comparative": "Termly Comparative Analysis", "grade-view": "Grade Level Breakdown", "least-learned": "Least Learned Competencies",
    "data-input": "Fast Data Entry & Upload", "manage-records": "Manage Records"
  },
  content: [
    { key: "login.org", page: "Login page", label: "Organization line", def: "Schools Division of Davao del Norte, Region XI", max: 120 },
    { key: "login.title", page: "Login page", label: "System title", def: "Division Assessment Consolidation System", max: 120 },
    { key: "login.scale_title", page: "Login page", label: "Rating scale heading", def: "How results are rated (Mean Percentage Score)", max: 120 },
    { key: "login.desc", page: "Login page", label: "Description", def: "MAPEH, SPA, SPS, SPFL and IPED assessment results, consolidated by district, term and key stage into the report the Division submits.", max: 400, multiline: true },
    { key: "login.foot", page: "Login page", label: "Footer line", def: "Department of Education, Republic of the Philippines", max: 120 },
    { key: "login.card_title", page: "Login page", label: "Sign-in heading", def: "Sign in", max: 60 },
    { key: "login.card_text", page: "Login page", label: "Sign-in instruction", def: "Use the username issued to your district or the Division office.", max: 200 },
    { key: "login.button", page: "Login page", label: "Sign-in button", def: "Log In", max: 30 },
    { key: "header.org", page: "Page header (all screens)", label: "Header line (before the school year)", def: "Republic of the Philippines | Region XI SDO Davao del Norte", max: 160 },
    { key: "sidebar.subtitle", page: "Menu (all screens)", label: "Menu subtitle", def: "MAPEH, SPA, SPS, SPFL & IPED MATRIX", max: 80 },
    { key: "view.division", page: "Screen headings", label: "Division Summary", def: "Division Summary View", max: 60 },
    { key: "view.district-view", page: "Screen headings", label: "District Profile", def: "District Profile View", max: 60 },
    { key: "view.comparative", page: "Screen headings", label: "Comparative Analysis", def: "Termly Comparative Analysis", max: 60 },
    { key: "view.dashboard", page: "Screen headings", label: "Dashboard", def: "Performance Dashboard", max: 60 },
    { key: "view.data-input", page: "Screen headings", label: "Data Entry", def: "Fast Data Entry & Upload", max: 60 },
    { key: "view.least-learned", page: "Screen headings", label: "Least Learned Competencies", def: "Least Learned Competencies", max: 60 },
    { key: "view.grade-view", page: "Screen headings", label: "Grade Level Breakdown", def: "Grade Level Breakdown", max: 60 },
    { key: "view.reports", page: "Screen headings", label: "Reports", def: "Reports & Signatories", max: 60 },
    { key: "view.settings", page: "Screen headings", label: "Settings & Branding", def: "Settings & Branding", max: 60 },
    { key: "view.manage-records", page: "Screen headings", label: "Manage Records", def: "Manage Records", max: 60 },
    { key: "view.schools", page: "Screen headings", label: "Schools & Accounts", def: "Schools & Accounts", max: 60 },
    { key: "dataentry.drop_title", page: "Data entry", label: "Upload box heading", def: "Drag & Drop District Excel File Here or Click to Browse", max: 120 },
    { key: "dataentry.drop_text", page: "Data entry", label: "Upload box instruction", def: "Upload district spreadsheets containing School Year, Baseline MPS (%), Current MPS (%), and at least 3 least learned competencies per grade level.", max: 300, multiline: true }
  ],
  // image positions an administrator can fill from the media library (see public.site_media_slots)
  slots: [
    { slot: "brand.logo", label: "Brand logo", where: "Login page and menu header (not shown when empty)", note: "Square or wide logo, PNG/JPEG/WebP, up to 2 MB." },
    { slot: "print.header_logo", label: "Printed report header logo", where: "Top of every printed report", note: "Replaces the logo set in Settings & Branding." },
    { slot: "print.footer_logo_1", label: "Printed report footer logo 1", where: "Bottom of printed reports", note: "" },
    { slot: "print.footer_logo_2", label: "Printed report footer logo 2", where: "Bottom of printed reports", note: "" },
    { slot: "print.footer_logo_3", label: "Printed report footer logo 3", where: "Bottom of printed reports", note: "" }
  ]
};
