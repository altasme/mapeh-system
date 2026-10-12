/* QA STAND-IN for @supabase/supabase-js (browser). Used ONLY by tools/qa; never deployed.
   It keeps tables in memory and imitates the parts of PostgREST / RLS / Auth the app relies on:
   1000-row response cap, range(), count/head, embedded districts(name), constraint errors, role-based access.
   It proves the app's logic. It does NOT replace supabase/tests/rls_matrix.sql, which tests the real policies. */
(function () {
  const S = window.__STUB;              // { districts, profiles, passwords, records, notes, settings }
  const T = {
    districts: S.districts, profiles: S.profiles, assessment_records: S.records,
    comparative_notes: S.notes, app_settings: [{ id: 1, data: S.settings }]
  };
  let nextId = Math.max(0, ...S.records.map(r => r.id || 0)) + 1;
  let nextNoteId = 1;
  const listeners = [];
  const key = 'stub_session';
  const sess = () => { try { return JSON.parse(sessionStorage.getItem(key)); } catch (_) { return null; } };
  const me = () => { const s = sess(); return s ? T.profiles.find(p => p.id === s.user.id) : null; };
  const sessionOk = () => { const p = me(); return !!p && p.active !== false && !p.must_change_password; };
  const isDivision = () => { const p = me(); return sessionOk() && (p.role === 'admin' || p.role === 'supervisor'); };
  const distName = id => (T.districts.find(d => d.id === id) || {}).name;
  const err = (code, message) => ({ code, message });
  const net = () => window.__STUB_OFFLINE ? { name: 'TypeError', message: 'Failed to fetch' } : null;
  const levelOf = g => ['Grade 1','Grade 2','Grade 3','Grade 4','Grade 5','Grade 6'].includes(g) ? 'elementary' : ['Grade 7','Grade 8','Grade 9','Grade 10','Grade 11','Grade 12'].includes(g) ? 'secondary' : null;
  const coordScope = (districtId, level) => { const p = me(); return sessionOk() && p.role === 'district_coordinator' && districtId === p.district_id && !!level && level === p.education_level; };

  function canRead(table, row) {
    const p = me(); if (!p) return false;
    if (table === 'profiles') return row.id === p.id;
    if (table === 'assessment_records') return isDivision() || coordScope(row.district_id, levelOf(row.grade_level));
    if (table === 'comparative_notes') return isDivision() || (sessionOk() && p.role === 'district_coordinator' && row.district_scope === distName(p.district_id) && row.education_level === p.education_level);
    return true; // districts, app_settings
  }
  function canWrite(table, op, row) {
    const p = me(); if (!p) return false;
    if (table === 'assessment_records') {
      if (op === 'delete') return isDivision();
      return isDivision() || coordScope(row.district_id, levelOf(row.grade_level));
    }
    if (table === 'comparative_notes') return op !== 'delete' && canRead('comparative_notes', row);
    if (table === 'districts' || table === 'app_settings') return op === 'update' && isDivision();
    return false;
  }
  function check(table, r) {
    if (table !== 'assessment_records') return null;
    if (!levelOf(r.grade_level)) return err('23502', 'null value in column "education_level" of relation "assessment_records" violates not-null constraint');
    const bad = c => err('23514', 'new row for relation "assessment_records" violates check constraint "assessment_records_' + c + '_check"');
    if (!/^[0-9]{4}-[0-9]{4}$/.test(r.sy)) return bad('sy');
    if (!['Term 1', 'Term 2', 'Term 3'].includes(r.term)) return bad('term');
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
          if (this.table === 'assessment_records') { r.created_by = me().id; r.education_level = levelOf(r.grade_level); }
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
        const hits = tbl.filter(r => canRead(this.table, r) && match(r));
        for (const r of hits) { if (!canWrite(this.table, 'update', Object.assign({}, r, this.vals)) && canRead(this.table, r) && this.table !== 'districts' && this.table !== 'app_settings' && this.table !== 'profiles') return { data: null, error: err('42501', 'new row violates row-level security policy for table "' + this.table + '"'), count: null }; }
        const upd = hits.filter(r => canWrite(this.table, 'update', Object.assign({}, r, this.vals)));
        upd.forEach(r => { if (this.table === 'assessment_records' && this.vals.grade_level) this.vals.education_level = levelOf(this.vals.grade_level); });
        for (const r of upd) { const c = check(this.table, Object.assign({}, r, this.vals)); if (c) return { data: null, error: c, count: null }; }
        upd.forEach(r => Object.assign(r, this.vals));
        return { data: this.ret ? upd.map(r => ({ id: r.id })) : null, error: null, count: this.cnt ? upd.length : null };
      }
      if (this.op === 'delete') {
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
