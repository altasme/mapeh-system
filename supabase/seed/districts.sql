-- districts.sql: 11 districts and the client's existing coordinator defaults, verbatim (stars 5 and 6)
insert into public.districts (name, coordinator_name, coordinator_position, sort_order) values
  ('Asuncion',        'Dr. Juan Dela Cruz',        'Public Schools District Supervisor', 1),
  ('B.E. Dujali',     'Maria Clara Santos',        'District Assessment Coordinator',    2),
  ('Carmen',          'Pedro Penduko',             'Principal In-Charge',                3),
  ('Kapalong East',   'Ana Rosa Reyes',            'Public Schools District Supervisor', 4),
  ('Kapalong West',   'Roberto Garcia',            'District Assessment Coordinator',    5),
  ('New Corella',     'Elena Torralba',            'Public Schools District Supervisor', 6),
  ('San Isidro',      'Gabriel Fernandez',         'Principal In-Charge',                7),
  ('Sto. Tomas East', 'Corazon Aquino-Dela Cruz',  'Public Schools District Supervisor', 8),
  ('Sto. Tomas West', 'Ramon Magsaysay Jr.',       'District Assessment Coordinator',    9),
  ('Talaingod',       'Bayanihan Datu',            'Principal In-Charge',                10),
  ('Langilan',        'Luzviminda Salcedo',        'Public Schools District Supervisor', 11);

-- When migration 0006 (coordinators by level) is already applied, give both levels the same starting details.
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'districts' and column_name = 'elem_coordinator_name') then
    update public.districts set
      elem_coordinator_name = coordinator_name, elem_coordinator_position = coordinator_position,
      sec_coordinator_name = coordinator_name, sec_coordinator_position = coordinator_position
    where elem_coordinator_name = '' and sec_coordinator_name = '';
  end if;
end $$;
