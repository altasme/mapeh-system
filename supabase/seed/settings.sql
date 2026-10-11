-- settings.sql: app_settings row from the client's current defaults
insert into public.app_settings (id, data) values (1, '{
  "sy": "",
  "sigPrepName": "JUAN DELA CRUZ", "sigPrepPos": "District Coordinator",
  "sigCheckName": "MARIA SANTOS", "sigCheckPos": "Education Program Supervisor",
  "sigNoteName": "DR. ALBERTO R. REYES", "sigNotePos": "Schools Division Superintendent",
  "headerLogo": "", "headerL1": "Republic of the Philippines", "headerL2": "Department of Education",
  "headerL3": "REGION XI", "headerL4": "SCHOOLS DIVISION OF DAVAO DEL NORTE",
  "footerLogo1": "", "footerLogo2": "", "footerLogo3": "",
  "footerAddress": "Mankilam, Tagum City, Davao del Norte", "footerPhone": "(084) 823 5170",
  "footerEmail": "depeddavnor.sdo@deped.gov.ph", "footerWebsite": "www.depeddavnor.ph",
  "footerFacebook": "DepEd Davao del Norte"
}'::jsonb);
