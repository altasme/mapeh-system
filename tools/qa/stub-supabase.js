/* QA STAND-IN for @supabase/supabase-js (browser). Used ONLY by tools/qa; never deployed.
   It keeps tables in memory and imitates the parts of PostgREST / RLS / Auth the app relies on:
   1000-row response cap, range(), count/head, embedded districts(name), constraint errors, role-based access.
   It proves the app's logic. It does NOT replace supabase/tests/rls_matrix.sql, which tests the real policies. */
(function () {
  const S = window.__STUB;              // { districts, profiles, passwords, records, notes, settings }
  S.schools = S.schools || []; S.school_programs = S.school_programs || [];
  const T = {
    districts: S.districts, profiles: S.profiles, assessment_records: S.records,
    comparative_notes: S.notes, app_settings: [{ id: 1, data: S.settings }], schools: S.schools, school_programs: S.school_programs
  };
  let nextSchoolId = Math.max(0, ...S.schools.map(x => x.id)) + 1;
  let nextId = Math.max(0, ...S.records.map(r => r.id || 0)) + 1;
  let nextNoteId = 1;
  const listeners = [];
  const key = 'stub_session';
  const sess = () => { try { return JSON.parse(sessionStorage.getItem(key)); } catch (_) { return null; } };
  const me = () => { const s = sess(); return s ? T.profiles.find(p => p.id === s.user.id) : null; };
  const sessionOk = () => { const p = me(); return !!p && p.active !== false; };   // migration 0008: no password gate
  const isDivision = () => { const p = me(); return sessionOk() && (p.role === 'admin' || p.role === 'supervisor'); };
  const distName = id => (T.districts.find(d => d.id === id) || {}).name;
  const err = (code, message) => ({ code, message });
  const net = () => window.__STUB_OFFLINE ? { name: 'TypeError', message: 'Failed to fetch' } : null;
  const levelOf = g => ['Grade 1','Grade 2','Grade 3','Grade 4','Grade 5','Grade 6'].includes(g) ? 'elementary' : ['Grade 7','Grade 8','Grade 9','Grade 10','Grade 11','Grade 12'].includes(g) ? 'secondary' : null;
  const coordScope = (districtId, level) => { const p = me(); return sessionOk() && p.role === 'district_coordinator' && districtId === p.district_id && !!level && level === p.education_level; };

  const isDel = r => r.deleted_at !== undefined && r.deleted_at !== null;
  const WRITABLE = ['sy','term','district_id','school','key_stage','grade_level','learning_area','baseline_mps','mps','pct75','proficiency_level','least_learned','school_id','baseline_sy'];
  const pl = m => m >= 90 ? 'Advanced' : m >= 85 ? 'Proficient' : m >= 80 ? 'Approaching Proficiency' : m >= 75 ? 'Developing' : 'Beginning';
  // mirror of public.app_mapeh_rule_problem()
  const LEG = ['MAPEH - Music & Arts', 'MAPEH - PE & Health'], COMP = ['MAPEH - Music', 'MAPEH - Arts', 'MAPEH - PE', 'MAPEH - Health'];
  const ruleProblem = (g, a) => {
    if (a !== 'MAPEH - Overall' && !COMP.includes(a) && !LEG.includes(a)) return null;
    if (['Grade 1','Grade 2','Grade 3'].includes(g) && a !== 'MAPEH - Overall') return 'Grades 1 to 3 are recorded as overall MAPEH only. Music, Arts, PE and Health are not recorded separately for these grades.';
    if (['Grade 4','Grade 5','Grade 6','Grade 7','Grade 8','Grade 9','Grade 10'].includes(g) && LEG.includes(a)) return 'Grades 4 to 10 are recorded as overall MAPEH plus Music, Arts, PE and Health. The combined Music & Arts and PE & Health areas are no longer used.';
    if (['Grade 11','Grade 12'].includes(g)) return 'MAPEH is not assessed in Grades 11 and 12.';
    return null;
  };
  const canSeeRecord = r => (isDivision() || coordScope(r.district_id, levelOf(r.grade_level)));
  // school accounts (migration 0010): one school, its program(s) only, its district, never deleted rows
  const isSchoolUser = () => { const p = me(); return sessionOk() && !!p && p.role === 'school'; };
  const progOf = a => /^(SPA|SPS|SPFL) - /.test(a || '') ? 'special_programs' : /^IPED - /.test(a || '') ? 'iped' : null;
  const schoolProgs = id => T.school_programs.filter(x => x.school_id === id).map(x => x.program);
  const schoolDistrict = id => (T.schools.find(x => x.id === id) || {}).district_id;
  const schoolOk = r => { if (!isSchoolUser() || r.school_id == null) return false; const p = me(); const pr = progOf(r.learning_area); const sc = T.schools.find(x => x.id === p.school_id);
    return r.school_id === p.school_id && !!sc && sc.active && !!pr && schoolProgs(p.school_id).includes(pr) && !isDel(r); };
  const schoolWriteOk = r => schoolOk(r) && r.district_id === schoolDistrict(me().school_id);

  // mirror of the school rules in app_records_guard()
  function schoolGuard(row, old) {
    if (row.school_id == null) return null;
    const sc = T.schools.find(x => x.id === row.school_id);
    if (!sc) return 'That school was not found.';
    if (sc.district_id !== row.district_id) return 'That school belongs to a different district.';
    if ((!old || old.school_id !== row.school_id) && !sc.active) return 'That school is inactive.';
    const pr = progOf(row.learning_area);
    if (pr && (!old || old.school_id !== row.school_id || old.learning_area !== row.learning_area) && !schoolProgs(sc.id).includes(pr)) return 'That school is not classified under the program of this learning area.';
    row.school = sc.name; return null;
  }
  function canRead(table, row) {
    const p = me(); if (!p) return false;
    if (table === 'profiles') return row.id === p.id;
    if (table === 'assessment_records') return (canSeeRecord(row) && (!isDel(row) || isDivision())) || schoolOk(row);
    if (table === 'schools') return isDivision() || (sessionOk() && p.role === 'district_coordinator' && row.district_id === p.district_id) || (isSchoolUser() && row.id === p.school_id);
    if (table === 'school_programs') return canRead('schools', T.schools.find(x => x.id === row.school_id) || {});
    if (table === 'comparative_notes') return isDivision() || (sessionOk() && p.role === 'district_coordinator' && row.district_scope === distName(p.district_id) && row.education_level === p.education_level);
    return true; // districts, app_settings
  }
  function canWrite(table, op, row) {
    const p = me(); if (!p) return false;
    if (table === 'assessment_records') {
      if (op === 'delete') return false;   // direct DELETE is revoked; deleting goes through the app_delete_* functions
      return isDivision() || coordScope(row.district_id, levelOf(row.grade_level)) || schoolWriteOk(row);
    }
    if (table === 'comparative_notes') return op !== 'delete' && canRead('comparative_notes', row);
    if (table === 'schools' || table === 'school_programs') return false;   // written only through the app_save_school / app_import_schools functions
    if (table === 'districts' || table === 'app_settings') return op === 'update' && isDivision();
    return false;
  }
  function check(table, r) {
    if (table !== 'assessment_records') return null;
    if (!levelOf(r.grade_level)) return err('23502', 'null value in column "education_level" of relation "assessment_records" violates not-null constraint');
    const bad = c => err('23514', 'new row for relation "assessment_records" violates check constraint "assessment_records_' + c + '_check"');
    if (!/^[0-9]{4}-[0-9]{4}$/.test(r.sy)) return bad('sy');
    if (!['Term 1', 'Term 2', 'Term 3'].includes(r.term)) return bad('term');
    if (r.baseline_sy != null && !/^[0-9]{4}-[0-9]{4}$/.test(r.baseline_sy)) return bad('baseline_sy');
    for (const c of ['baseline_mps', 'mps', 'pct75']) {
      if (r[c] === null || r[c] === undefined || Number.isNaN(r[c])) return err('23502', 'null value in column "' + c + '" violates not-null constraint');
      if (r[c] < 0 || r[c] > 100) return bad(c);
    }
    if (!T.districts.find(d => d.id === r.district_id)) return err('23503', 'insert or update on table "assessment_records" violates foreign key constraint');
    return null;
  }

  class Q {
    constructor(table) { this.table = table; this.f = []; this.op = 'select'; this.ret = true; this.cnt = null; this.head = false; this.ord = null; this.rng = null; this.one = null; }
    select(cols, o) { if (this.op !== 'select') { this.ret = true; this.cols = cols; } else { this.cols = cols; } if (o) { this.cnt = o.count || null; this.head = !!o.head; } return this; }
    insert(rows, o) { this.op = 'insert'; this.rows = [].concat(rows); this.ret = false; if (o) this.cnt = o.count || null; return this; }
    upsert(rows, o) { this.op = 'upsert'; this.rows = [].concat(rows); this.ret = false; this.onConflict = (o && o.onConflict) || null; return this; }
    update(v, o) { this.op = 'update'; this.vals = v; this.ret = false; if (o) this.cnt = o.count || null; return this; }
    delete(o) { this.op = 'delete'; this.ret = false; if (o) this.cnt = o.count || null; return this; }
    is(c, v) { this.f.push(r => (r[c] === undefined ? null : r[c]) === v); return this; }
    not(c, op, v) { this.f.push(r => !(op === 'is' ? (r[c] === undefined ? null : r[c]) === v : r[c] === v)); return this; }
    limit(n) { this.lim = n; return this; }
    eq(c, v) { this.f.push(r => r[c] === v); return this; }
    neq(c, v) { this.f.push(r => r[c] !== v); return this; }
    gt(c, v) { this.f.push(r => r[c] > v); return this; }
    in(c, vs) { this.f.push(r => vs.includes(r[c])); return this; }
    order(c) { this.ord = c; return this; }
    range(a, b) { this.rng = [a, b]; return this; }
    maybeSingle() { this.one = 'maybe'; return this; }
    single() { this.one = 'single'; return this; }
    then(res, rej) { return Promise.resolve().then(() => this.run()).then(res, rej); }
    embed(row) {
      const out = Object.assign({}, row);
      if (this.table === 'profiles' && /districts\(/.test(this.cols || '')) { const d = T.districts.find(x => x.id === row.district_id); out.districts = d ? { name: d.name } : null; }
      return out;
    }
    run() {
      const e = net(); if (e) return Promise.reject(e);
      const tbl = T[this.table];
      if (!tbl) return { data: null, error: err('42P01', 'relation does not exist'), count: null };
      if (!me()) return { data: null, error: err('42501', 'permission denied for table ' + this.table), count: null };
      const match = r => this.f.every(fn => fn(r));
      if (this.op === 'select') {
        let rows = tbl.filter(r => canRead(this.table, r) && match(r));
        const total = rows.length;
        if (this.ord) rows = rows.slice().sort((a, b) => a[this.ord] < b[this.ord] ? -1 : a[this.ord] > b[this.ord] ? 1 : 0);
        if (this.rng) rows = rows.slice(this.rng[0], this.rng[1] + 1);
        if (this.lim) rows = rows.slice(0, this.lim);
        rows = rows.slice(0, 1000);                                   // PostgREST max-rows
        const count = this.cnt ? total : null;
        if (this.head) return { data: null, error: null, count };
        let data = rows.map(r => this.embed(r));
        if (this.one) return { data: data[0] || null, error: null, count };
        return { data, error: null, count };
      }
      if (this.op === 'insert' || this.op === 'upsert') {
        const staged = [];
        for (const r0 of this.rows) {
          const r = Object.assign({}, r0);
          if (this.table === 'assessment_records') {
            if (Object.keys(r0).some(k => !WRITABLE.includes(k))) return { data: null, error: err('42501', 'permission denied for table assessment_records'), count: null };
            const rp = ruleProblem(r.grade_level, r.learning_area);
            if (rp) return { data: null, error: err('23514', rp), count: null };
            const sg = schoolGuard(r, null); if (sg) return { data: null, error: err('P0001', sg), count: null };
            r.created_by = me().id; r.education_level = levelOf(r.grade_level); r.is_demo = false;
            if (typeof r.mps === 'number') r.proficiency_level = pl(r.mps);
          }
          if (this.table === 'comparative_notes' && r.education_level === undefined) r.education_level = 'all';
          if (this.op === 'upsert') {
            const k = (this.onConflict || '').split(',');
            const ex = tbl.find(x => k.every(c => x[c] === r[c]));
            if (!canWrite(this.table, 'insert', r)) return { data: null, error: err('42501', 'new row violates row-level security policy for table "' + this.table + '"'), count: null };
            staged.push({ ex, r }); continue;
          }
          if (!canWrite(this.table, 'insert', r)) return { data: null, error: err('42501', 'new row violates row-level security policy for table "' + this.table + '"'), count: null };
          const c = check(this.table, r); if (c) return { data: null, error: c, count: null };
          staged.push({ r });
        }
        const out = [];
        staged.forEach(({ ex, r }) => {
          if (ex) { Object.assign(ex, r); out.push({ id: ex.id }); }
          else { r.id = this.table === 'comparative_notes' ? nextNoteId++ : nextId++; tbl.push(r); out.push({ id: r.id }); }
        });
        return { data: this.ret ? out : null, error: null, count: this.cnt ? staged.length : null };
      }
      if (this.op === 'update') {
        if (this.table === 'assessment_records' && Object.keys(this.vals).some(k => !WRITABLE.includes(k))) return { data: null, error: err('42501', 'permission denied for table assessment_records'), count: null };
        const hits = tbl.filter(r => canRead(this.table, r) && match(r) && !(this.table === 'assessment_records' && isDel(r)));
        if (this.table === 'assessment_records') {
          for (const r of hits) { const sg = schoolGuard(Object.assign({}, r, this.vals), r); if (sg) return { data: null, error: err('P0001', sg), count: null }; }
        }
        if (this.table === 'assessment_records') {
          for (const r of hits) {
            if ((this.vals.grade_level !== undefined && this.vals.grade_level !== r.grade_level) || (this.vals.learning_area !== undefined && this.vals.learning_area !== r.learning_area)) {
              const rp = ruleProblem(this.vals.grade_level !== undefined ? this.vals.grade_level : r.grade_level, this.vals.learning_area !== undefined ? this.vals.learning_area : r.learning_area);
              if (rp) return { data: null, error: err('23514', rp), count: null };
            }
          }
        }
        for (const r of hits) { if (!canWrite(this.table, 'update', Object.assign({}, r, this.vals)) && canRead(this.table, r) && this.table !== 'districts' && this.table !== 'app_settings' && this.table !== 'profiles') return { data: null, error: err('42501', 'new row violates row-level security policy for table "' + this.table + '"'), count: null }; }
        const upd = hits.filter(r => canWrite(this.table, 'update', Object.assign({}, r, this.vals)));
        upd.forEach(r => { if (this.table === 'assessment_records' && this.vals.grade_level) this.vals.education_level = levelOf(this.vals.grade_level); });
        if (this.table === 'assessment_records' && this.vals.school_id != null) { const sc = T.schools.find(x => x.id === this.vals.school_id); if (sc) this.vals.school = sc.name; }
        if (this.table === 'assessment_records') { if (typeof this.vals.mps === 'number') this.vals.proficiency_level = pl(this.vals.mps); this.vals.updated_by = me().id; }
        for (const r of upd) { const c = check(this.table, Object.assign({}, r, this.vals)); if (c) return { data: null, error: c, count: null }; }
        upd.forEach(r => Object.assign(r, this.vals));
        return { data: this.ret ? upd.map(r => ({ id: r.id })) : null, error: null, count: this.cnt ? upd.length : null };
      }
      if (this.op === 'delete') {
        if (this.table === 'assessment_records') return { data: null, error: err('42501', 'permission denied for table assessment_records'), count: null };
        const hits = tbl.filter(r => canRead(this.table, r) && match(r) && canWrite(this.table, 'delete', r));
        hits.forEach(r => tbl.splice(tbl.indexOf(r), 1));
        return { data: null, error: null, count: this.cnt ? hits.length : null };
      }
    }
  }

  window.supabase = {
    createClient() {
      return {
        from: t => new Q(t),
        rpc(name, a) {
          return Promise.resolve().then(() => {
            const e = net(); if (e) throw e;
            const T2 = T.assessment_records, now = new Date().toISOString();
            if (!sessionOk()) return { data: null, error: err('42501', 'Not allowed.') };
            const mark = (rows, reason) => { rows.forEach(r => { r.deleted_at = now; r.deleted_by = me().id; r.delete_reason = reason; }); return rows.length; };
            if (name === 'app_delete_records') {
              const ids = Array.from(new Set(a.p_ids || []));
              const rows = T2.filter(r => ids.includes(r.id) && !isDel(r));
              if (rows.some(r => !canSeeRecord(r))) return { data: null, error: err('42501', 'You do not have access to one or more of these records.') };
              return { data: mark(rows, (a.p_reason || '').trim() || null), error: null };
            }
            if (name === 'app_restore_records') {
              if (!isDivision()) return { data: null, error: err('42501', 'Only the division team can restore records.') };
              const rows = T2.filter(r => (a.p_ids || []).includes(r.id) && isDel(r));
              rows.forEach(r => { r.deleted_at = null; r.deleted_by = null; r.delete_reason = null; });
              return { data: rows.length, error: null };
            }
            if (name === 'app_delete_records_by_sy' || name === 'app_delete_all_records') {
              if (!isDivision()) return { data: null, error: err('42501', 'Only the division team can delete in bulk.') };
              const rows = T2.filter(r => !isDel(r) && (name === 'app_delete_all_records' || r.sy === a.p_sy));
              return { data: mark(rows, name === 'app_delete_all_records' ? 'Bulk delete: all records' : 'Bulk delete: school year ' + a.p_sy), error: null };
            }
            const need = () => isDivision() ? null : { data: null, error: err('42501', 'Only a Supervisor or Admin can manage schools.') };
            const fail = m => ({ data: null, error: err('P0001', m) });
            if (name === 'app_save_school') {
              const d0 = need(); if (d0) return d0;
              const nm = String(a.p_name || '').trim(); const progs = Array.from(new Set(a.p_programs || []));
              if (!nm) return fail('Enter the school name (200 characters at most).');
              if (!T.districts.find(x => x.id === a.p_district_id)) return fail('Choose a district.');
              if (!progs.length || progs.some(x => !['special_programs', 'iped'].includes(x))) return fail('Choose Special Programs, IPED, or both.');
              const dup = T.schools.find(x => x.district_id === a.p_district_id && x.name.trim().toLowerCase() === nm.toLowerCase() && x.id !== a.p_id);
              let sc;
              if (a.p_id == null) { if (dup) return fail('A school with that name already exists in this district. Open it and add the program there instead.'); sc = { id: nextSchoolId++, name: nm, district_id: a.p_district_id, active: a.p_active !== false }; T.schools.push(sc); }
              else { sc = T.schools.find(x => x.id === a.p_id); if (!sc) return fail('School not found.');
                const linked = T2.filter(x => x.school_id === sc.id);
                if (sc.district_id !== a.p_district_id && linked.length) return fail('This school has linked records, so it cannot be moved to another district.');
                if (T.school_programs.some(x => x.school_id === sc.id && !progs.includes(x.program) && linked.some(r => !isDel(r) && progOf(r.learning_area) === x.program))) return fail('Cannot remove a program that this school already has records for.');
                if (dup) return fail('A school with that name already exists in this district.');
                sc.name = nm; sc.district_id = a.p_district_id; if (a.p_active != null) sc.active = a.p_active; }
              for (let i = T.school_programs.length - 1; i >= 0; i--) if (T.school_programs[i].school_id === sc.id && !progs.includes(T.school_programs[i].program)) T.school_programs.splice(i, 1);
              progs.forEach(pg => { if (!T.school_programs.some(x => x.school_id === sc.id && x.program === pg)) T.school_programs.push({ school_id: sc.id, program: pg }); });
              return { data: sc.id, error: null };
            }
            if (name === 'app_import_schools') {
              const d0 = need(); if (d0) return d0;
              const rows = a.p_rows || [], bad = [], plan = [];
              rows.forEach((r, i) => { const nm = String(r.name || '').trim(); const d = T.districts.find(x => x.name.toLowerCase() === String(r.district || '').trim().toLowerCase()); const pg = Array.from(new Set(r.programs || []));
                if (!nm) bad.push('row ' + (i + 2) + ': school name'); else if (!d) bad.push('row ' + (i + 2) + ': unknown district "' + (r.district || '') + '"'); else if (!pg.length) bad.push('row ' + (i + 2) + ': program must be Special Programs, IPED or Both'); else plan.push({ nm, d, pg }); });
              if (bad.length) return fail('Nothing was imported. ' + bad.length + ' row(s) have problems: ' + bad.slice(0, 5).join('; '));
              let created = 0, updated = 0;
              plan.forEach(({ nm, d, pg }) => { let sc = T.schools.find(x => x.district_id === d.id && x.name.trim().toLowerCase() === nm.toLowerCase());
                if (!sc) { sc = { id: nextSchoolId++, name: nm, district_id: d.id, active: true }; T.schools.push(sc); created++; } else updated++;
                pg.forEach(p2 => { if (!T.school_programs.some(x => x.school_id === sc.id && x.program === p2)) T.school_programs.push({ school_id: sc.id, program: p2 }); }); });
              return { data: { created, updated }, error: null };
            }
            if (name === 'app_count_linkable_records' || name === 'app_link_school_records') {
              if (!isDivision()) return name === 'app_count_linkable_records' ? { data: 0, error: null } : { data: null, error: err('42501', 'Only a Supervisor or Admin can link records.') };
              const sc = T.schools.find(x => x.id === a.p_school_id); if (!sc) return { data: 0, error: null };
              const rows = T2.filter(r => r.school_id == null && !isDel(r) && r.district_id === sc.district_id && String(r.school || '').trim().toLowerCase() === sc.name.trim().toLowerCase() && progOf(r.learning_area) && schoolProgs(sc.id).includes(progOf(r.learning_area)));
              if (name === 'app_link_school_records') rows.forEach(r => { r.school_id = sc.id; r.school = sc.name; });
              return { data: rows.length, error: null };
            }
            if (name === 'app_create_school_account') {
              if (!isDivision()) return { data: null, error: err('42501', 'Only a Supervisor or Admin can create school accounts.') };
              const u = String(a.p_username || '').trim().toLowerCase(), dn = String(a.p_display_name || '').trim();
              if (!/^[a-z0-9][a-z0-9._-]{2,39}$/.test(u)) return fail('Username must be 3 to 40 characters: lowercase letters, numbers, dot, dash or underscore.');
              if (!dn) return fail('Enter a display name (120 characters at most).');
              if (String(a.p_password || '').length < 8) return fail('The password must be at least 8 characters.');
              const sc = T.schools.find(x => x.id === a.p_school_id); if (!sc) return fail('School not found.'); if (!sc.active) return fail('That school is inactive.');
              if (!schoolProgs(sc.id).length) return fail('Classify the school as Special Programs or IPED first.');
              if (T.profiles.some(x => x.school_id === sc.id && x.active)) return fail('This school already has an active account.');
              if (T.profiles.some(x => x.username.toLowerCase() === u)) return fail('That username is already taken.');
              const id = 'school-' + u; T.profiles.push({ id, username: u, display_name: dn, role: 'school', district_id: sc.district_id, education_level: null, school_id: sc.id, active: true, must_change_password: false }); S.passwords[u] = a.p_password;
              return { data: id, error: null };
            }
            if (name === 'app_set_school_account_active') {
              if (!isDivision()) return { data: null, error: err('42501', 'Only a Supervisor or Admin can change school accounts.') };
              const pr = T.profiles.find(x => x.id === a.p_profile_id && x.school_id != null); if (!pr) return fail('That is not a school account.');
              if (a.p_active && T.profiles.some(x => x.school_id === pr.school_id && x.active && x.id !== pr.id)) return fail('This school already has another active account.');
              pr.active = !!a.p_active; return { data: null, error: null };
            }
            if (name === 'app_list_school_accounts') {
              if (!isDivision()) return { data: [], error: null };
              return { data: T.profiles.filter(x => x.school_id != null).map(x => { const sc = T.schools.find(y => y.id === x.school_id) || {}; return { profile_id: x.id, username: x.username, display_name: x.display_name, active: x.active, school_id: x.school_id, school_name: sc.name, district_name: (T.districts.find(d => d.id === sc.district_id) || {}).name, programs: schoolProgs(x.school_id) }; }), error: null };
            }
            if (name === 'app_edit_competency') {
              const code = String(a.p_code || '').trim(), desc = String(a.p_desc || '').trim();
              if (!desc) return { data: null, error: err('P0001', 'The competency description cannot be empty.') };
              if (desc.length > 500) return { data: null, error: err('P0001', 'The competency description is too long (500 characters at most).') };
              if (!code) return { data: null, error: err('P0001', 'Enter a competency code.') };
              const r = T2.find(x => x.id === a.p_id && !isDel(x) && (canSeeRecord(x) || schoolOk(x)));
              const ll = r && Array.isArray(r.least_learned) ? r.least_learned : null;
              if (!ll || a.p_index < 0 || a.p_index >= ll.length) return { data: null, error: err('P0001', 'That competency could not be found. Reload the page and try again.') };
              const el = ll[a.p_index], cur = typeof el === 'string' ? el : (el.desc || el.description || el.competency || '');
              if (cur.trim() !== String(a.p_old_desc || '').trim()) return { data: null, error: err('P0001', 'This competency was changed by someone else. Reload the page and try again.') };
              ll[a.p_index] = { code, desc }; r.updated_by = me().id;
              return { data: 1, error: null };
            }
            return { data: null, error: err('42883', 'function does not exist') };
          });
        },
        auth: {
          async getSession() { const e = net(); if (e) throw e; return { data: { session: sess() }, error: null }; },
          async signInWithPassword({ email, password }) {
            const e = net(); if (e) throw e;
            const u = email.split('@')[0];
            const p = T.profiles.find(x => x.username === u);
            if (!p || S.passwords[u] !== password) return { data: null, error: { status: 400, message: 'Invalid login credentials' } };
            const s = { user: { id: p.id, email } };
            sessionStorage.setItem(key, JSON.stringify(s));
            return { data: { session: s }, error: null };
          },
          async updateUser({ password }) {
            const e = net(); if (e) throw e;
            const sn = sess(); if (!sn) return { data: null, error: { status: 401, message: 'not signed in' } };
            const p = T.profiles.find(x => x.id === sn.user.id);
            if (S.passwords[p.username] === password) return { data: null, error: { status: 422, code: 'same_password', message: 'New password should be different from the old password.' } };
            S.passwords[p.username] = password; p.must_change_password = false;   // what the database trigger does
            return { data: { user: sn.user }, error: null };
          },
          async signOut() { sessionStorage.removeItem(key); listeners.forEach(f => f('SIGNED_OUT', null)); return { error: null }; },
          onAuthStateChange(f) { listeners.push(f); return { data: { subscription: { unsubscribe() {} } } }; }
        }
      };
    }
  };
})();
