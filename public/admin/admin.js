/* MAPEH admin panel (route /admin). Every privileged action is a database function that re-checks, on the server, that the
   caller is an active user with the admin role; this file only presents them. No service key or secret is ever used here. */
(() => {
'use strict';
const CFG = window.APP_CONFIG || {};
const REG = window.SITE_REGISTRY || { content: [], slots: [], views: {}, schoolYears: [] };
let _sb;
const sb = () => _sb || (_sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabasePublishableKey, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false } }));
const $ = (s, r = document) => r.querySelector(s);
const esc = s => String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmt = t => t ? new Date(t).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' }) : '-';
const IDLE_MS = 30 * 60 * 1000;
const ROLE_LABEL = { admin: 'Administrator', supervisor: 'Supervisor', district_coordinator: 'District Coordinator', school: 'School Account' };
const LEVEL_LABEL = { elementary: 'Elementary', secondary: 'Secondary' };
const PROGRAM_LABEL = { special_programs: 'Special Programs', iped: 'IPED' };
const S = { me: null, dirty: false, lookups: null, idleAt: Date.now() };

/* ---------- helpers ---------- */
function toast(msg, type = 'ok') {
  const el = document.createElement('div'); el.className = 'toast ' + type; el.textContent = msg;
  $('#toast-host').appendChild(el); setTimeout(() => el.remove(), type === 'err' ? 9000 : 4000);
}
function friendly(err) {
  if (!err) return 'Something went wrong.';
  const msg = String(err.message || ''), code = String(err.code || '');
  if (/failed to fetch|networkerror|load failed/i.test(msg) || err.name === 'AuthRetryableFetchError') return 'Could not reach the server. Nothing was saved.';
  if (code === '42501') return /Only an administrator/.test(msg) ? msg : 'You are not allowed to do that.';
  if (code === 'PGRST301' || /jwt expired/i.test(msg)) return 'Your session expired. Please sign in again.';
  return msg || 'Something went wrong.';
}
async function rpc(name, args) {
  const { data, error } = await sb().rpc(name, args || {});
  if (error) throw error;
  return data;
}
function setBusy(btn, on) { if (btn) btn.disabled = !!on; }
function randomPassword() {
  const a = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789', b = new Uint32Array(14); crypto.getRandomValues(b);
  return Array.from(b, v => a[v % a.length]).join('');
}
function confirmLeave() { return !S.dirty || confirm('You have unsaved changes. Leave without saving?'); }
window.addEventListener('beforeunload', e => { if (S.dirty) { e.preventDefault(); e.returnValue = ''; } });

/* ---------- modal ---------- */
function openModal(html, wide) {
  closeModal();
  const o = document.createElement('div'); o.className = 'overlay'; o.id = 'overlay';
  o.innerHTML = `<div class="modal${wide ? ' wide' : ''}" role="dialog" aria-modal="true">${html}</div>`;
  $('#modal-host').appendChild(o);
  const f = o.querySelector('input:not([type=hidden]), select, textarea, button'); if (f) f.focus();
  return o;
}
function closeModal() { const o = $('#overlay'); if (o) o.remove(); }
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeModal(); });

/* ---------- routes ---------- */
const ROUTES = {
  '/admin/dashboard': { title: 'Dashboard', nav: 'Dashboard', render: pDashboard },
  '/admin/users': { title: 'User Management', nav: 'User Management', render: pUsers },
  '/admin/roles': { title: 'Roles and Permissions', nav: 'Roles and Permissions', render: pRoles },
  '/admin/content': { title: 'Website Content', nav: 'Website Content', render: pContent },
  '/admin/media': { title: 'Image and Media Library', nav: 'Image and Media Library', render: pMedia },
  '/admin/settings': { title: 'Website Settings', nav: 'Website Settings', render: pSettings },
  '/admin/audit': { title: 'Audit Logs', nav: 'Audit Logs', render: pAudit },
  '/admin/account': { title: 'Account Settings', nav: 'Account Settings', render: pAccount }
};
const here = () => window.location.pathname.replace(/\/+$/, '') || '/admin';

function navigate(path, replace) {
  if (!confirmLeave()) return;
  S.dirty = false;
  if (replace) history.replaceState({}, '', path); else history.pushState({}, '', path);
  renderRoute();
}
window.addEventListener('popstate', () => { S.dirty = false; renderRoute(); });
document.addEventListener('click', e => {
  const a = e.target.closest('a[data-route]');
  if (a) { e.preventDefault(); document.body.classList.remove('nav-open'); navigate(a.getAttribute('href')); }
});

/* ---------- login / session ---------- */
function loginView(msg) {
  $('#app').innerHTML = `
  <div class="login-wrap">
    <div class="login-brand"><div class="rule"></div><h1>MAPEH Davao del Norte Assessment System</h1><p>Administration: users, website content, images and settings.</p></div>
    <div class="login-pane"><form class="login-card" id="login-form" autocomplete="on">
      <h2>Administrator sign in</h2><p class="sub">Only administrator accounts can open this area.</p>
      <div class="field"><label for="lu">Username</label><input type="text" id="lu" autocomplete="username" required></div>
      <div class="field"><label for="lp">Password</label><input type="password" id="lp" autocomplete="current-password" required></div>
      <div class="error" id="login-error" role="alert">${esc(msg || '')}</div>
      <button class="btn" type="submit" style="width:100%;justify-content:center;margin-top:6px" id="login-btn">Sign in</button>
      <p class="hint" style="margin-top:14px"><a href="/">Back to the assessment system</a></p>
    </form></div>
  </div>`;
}
const failKey = 'admin_login_fail';
async function handleLogin(ev) {
  ev.preventDefault();
  const err = $('#login-error'), btn = $('#login-btn');
  const f = JSON.parse(sessionStorage.getItem(failKey) || '{"n":0,"until":0}');
  if (f.until > Date.now()) { err.textContent = `Too many attempts. Wait ${Math.ceil((f.until - Date.now()) / 1000)} seconds and try again.`; return; }
  const u = $('#lu').value.trim().toLowerCase(), p = $('#lp').value;
  err.textContent = ''; setBusy(btn, true);
  try {
    const email = u.includes('@') ? u : `${u}@${CFG.authEmailDomain}`;
    const { error } = await sb().auth.signInWithPassword({ email, password: p });
    if (error) {
      f.n += 1; if (f.n >= 5) { f.until = Date.now() + 60000; f.n = 0; }   // courtesy delay; the server also rate-limits sign-ins
      sessionStorage.setItem(failKey, JSON.stringify(f));
      err.textContent = error.status === 400 ? 'Invalid username or password.' : friendly(error); return;
    }
    sessionStorage.removeItem(failKey);
    const ok = await enter(true);
    if (!ok) { await sb().auth.signOut(); loginView('This account is not authorized for administration.'); bindLogin(); }
  } catch (e) { err.textContent = friendly(e); } finally { setBusy(btn, false); }
}
function bindLogin() { const f = $('#login-form'); if (f) f.addEventListener('submit', handleLogin); }

async function enter(fresh) {
  const { data: { session } } = await sb().auth.getSession();
  if (!session) { loginView(); bindLogin(); return false; }
  const { data: p, error } = await sb().from('profiles').select('username, display_name, role, active').eq('id', session.user.id).maybeSingle();
  if (error || !p || !p.active || p.role !== 'admin') {
    try { await rpc('app_admin_log_denied'); } catch (_) { /* best effort */ }
    if (!fresh) deniedView();
    return false;
  }
  S.me = { id: session.user.id, username: p.username, name: p.display_name };
  if (fresh) { try { await rpc('app_admin_log_event', { p_action: 'login' }); } catch (_) { /* logged best effort */ } }
  shell();
  if (here() === '/admin' || !ROUTES[here()]) navigate('/admin/dashboard', true); else renderRoute();
  return true;
}
function deniedView() {
  $('#app').innerHTML = `<div class="login-wrap" style="grid-template-columns:1fr"><div class="login-pane"><div class="login-card">
    <h2>Not authorized</h2><p class="sub">You are signed in, but this account is not an administrator. Administrative functions are not available to it.</p>
    <a class="btn" href="/">Back to the assessment system</a> <button class="btn btn-secondary" id="denied-out">Sign out</button></div></div></div>`;
  $('#denied-out').addEventListener('click', async () => { await sb().auth.signOut(); loginView(); bindLogin(); });
}
async function logout(reason) {
  try { if (S.me) await rpc('app_admin_log_event', { p_action: 'logout' }); } catch (_) { /* best effort */ }
  await sb().auth.signOut(); S.me = null; S.dirty = false;
  history.replaceState({}, '', '/admin'); loginView(reason || ''); bindLogin();
}
['click', 'keydown', 'mousemove', 'touchstart'].forEach(ev => document.addEventListener(ev, () => { S.idleAt = Date.now(); }, { passive: true }));
setInterval(() => { if (S.me && Date.now() - S.idleAt > IDLE_MS) logout('You were signed out after 30 minutes of inactivity.'); }, 30000);

/* ---------- shell ---------- */
function shell() {
  $('#app').innerHTML = `
  <div class="shell">
    <aside class="side" id="side"><div class="brand"><strong>MAPEH Admin</strong><span>Davao del Norte</span></div>
      <nav>${Object.entries(ROUTES).map(([p, r]) => `<a href="${p}" data-route="1">${esc(r.nav)}</a>`).join('')}</nav>
      <button class="btn btn-secondary logout" data-act="logout">Logout</button></aside>
    <div class="main"><header class="top"><button class="btn btn-secondary btn-sm menu-btn" data-act="menu" aria-label="Open menu">Menu</button><h1 id="page-title"></h1>
      <div class="who"><strong>${esc(S.me.name)}</strong><br>${esc(S.me.username)}</div></header>
      <main class="content" id="page"></main></div>
  </div>`;
}
async function renderRoute() {
  if (!S.me) return;
  const path = here(), r = ROUTES[path] || ROUTES['/admin/dashboard'];
  document.querySelectorAll('.side nav a').forEach(a => a.removeAttribute('aria-current'));
  const cur = $(`.side nav a[href="${path}"]`); if (cur) cur.setAttribute('aria-current', 'page');
  $('#page-title').textContent = r.title; document.title = r.title + ' - MAPEH Admin';
  const page = $('#page'); page.innerHTML = '<p class="empty">Loading...</p>';
  try { await r.render(page); } catch (e) { page.innerHTML = `<div class="card"><h3>Could not load this page</h3><p class="error">${esc(friendly(e))}</p><button class="btn" data-act="reload">Try again</button></div>`; }
}
const ACT = {
  logout: () => logout(),
  menu: () => document.body.classList.toggle('nav-open'),
  reload: () => renderRoute()
};
document.addEventListener('click', e => {
  const t = e.target.closest('[data-act]'); if (!t) return;
  const fn = ACT[t.getAttribute('data-act')]; if (fn) fn(t, e);
});

async function lookups() {
  if (S.lookups) return S.lookups;
  const [d, s, sp] = await Promise.all([
    sb().from('districts').select('id, name, sort_order').order('sort_order'),
    sb().from('schools').select('id, name, district_id, active').order('name').range(0, 4999),
    sb().from('school_programs').select('school_id, program').range(0, 9999)]);
  if (d.error) throw d.error; if (s.error) throw s.error; if (sp.error) throw sp.error;
  const progs = {}; sp.data.forEach(x => { (progs[x.school_id] = progs[x.school_id] || []).push(x.program); });
  S.lookups = { districts: d.data, schools: s.data.map(x => ({ ...x, programs: (progs[x.id] || []).sort() })) };
  return S.lookups;
}
const progBadges = ps => (ps || []).map(p => `<span class="badge ${p === 'iped' ? 'iped' : 'sp'}">${esc(PROGRAM_LABEL[p] || p)}</span>`).join('');

/* ---------- Dashboard ---------- */
async function pDashboard(page) {
  const [st, act] = await Promise.all([rpc('app_admin_user_stats'), rpc('app_admin_activity', { p_limit: 8, p_offset: 0 })]);
  const by = st.by_role || {};
  page.innerHTML = `
  <div class="cards">
    <div class="stat"><strong>${st.total}</strong><span>Registered users</span></div>
    <div class="stat"><strong>${st.active}</strong><span>Active users</span></div>
    <div class="stat"><strong>${st.disabled}</strong><span>Disabled users</span></div>
    <div class="stat"><strong>${st.schools}</strong><span>Active schools${st.schools_total !== st.schools ? ` (${st.schools_total} listed)` : ''}</span></div>
  </div>
  <div class="card"><h3>Users by role</h3><div class="cards" style="margin:0">
    ${Object.keys(ROLE_LABEL).map(r => `<div class="stat"><strong>${by[r] || 0}</strong><span>${esc(ROLE_LABEL[r])}</span></div>`).join('')}</div></div>
  <div class="card"><h3>Recent administrative activity</h3>
    ${act.length ? `<div class="scroll"><table><thead><tr><th>When</th><th>Administrator</th><th>Action</th><th>Outcome</th></tr></thead><tbody>
      ${act.map(a => `<tr><td>${esc(fmt(a.at))}</td><td>${esc(a.actor_name || '-')}</td><td>${esc(a.action)}</td><td>${outcomeBadge(a.outcome)}</td></tr>`).join('')}</tbody></table></div>
      <p class="hint"><a href="/admin/audit" data-route="1">Open the full audit log</a></p>` : '<p class="empty">No administrative activity yet.</p>'}</div>
  <div class="card"><h3>Quick links</h3><p>
    <a class="btn btn-secondary" href="/admin/users" data-route="1">Manage users</a>
    <a class="btn btn-secondary" href="/admin/content" data-route="1">Edit website text</a>
    <a class="btn btn-secondary" href="/admin/media" data-route="1">Replace images</a>
    <a class="btn btn-secondary" href="/admin/settings" data-route="1">Website settings</a></p></div>`;
}
const outcomeBadge = o => `<span class="badge ${o === 'success' ? 'ok' : o === 'denied' ? 'warn' : 'off'}">${esc(o)}</span>`;

/* ---------- User management ---------- */
const U = { search: '', role: '', district: '', school: '', program: '', status: '', page: 0, size: 25, rows: [], total: 0 };
async function pUsers(page) {
  const L = await lookups();
  page.innerHTML = `
  <div class="card">
    <div class="toolbar">
      <div class="grow"><label for="u-search">Search</label><input type="search" id="u-search" placeholder="Username, name, school" value="${esc(U.search)}"></div>
      <div><label for="u-role">Role</label><select id="u-role"><option value="">All roles</option>${Object.entries(ROLE_LABEL).map(([k, v]) => `<option value="${k}" ${U.role === k ? 'selected' : ''}>${v}</option>`).join('')}</select></div>
      <div><label for="u-district">District</label><select id="u-district"><option value="">All districts</option>${L.districts.map(d => `<option value="${d.id}" ${U.district == d.id ? 'selected' : ''}>${esc(d.name)}</option>`).join('')}</select></div>
      <div><label for="u-school">School</label><select id="u-school"><option value="">All schools</option>${L.schools.map(s => `<option value="${s.id}" ${U.school == s.id ? 'selected' : ''}>${esc(s.name)}</option>`).join('')}</select></div>
      <div><label for="u-program">Program</label><select id="u-program"><option value="">All programs</option><option value="special_programs" ${U.program === 'special_programs' ? 'selected' : ''}>Special Programs</option><option value="iped" ${U.program === 'iped' ? 'selected' : ''}>IPED</option></select></div>
      <div><label for="u-status">Status</label><select id="u-status"><option value="">Any status</option><option value="active" ${U.status === 'active' ? 'selected' : ''}>Active</option><option value="disabled" ${U.status === 'disabled' ? 'selected' : ''}>Disabled</option></select></div>
      <div><button class="btn" id="u-new">Create user</button></div>
    </div>
    <div class="scroll" id="u-table"></div><div class="pager" id="u-pager"></div>
  </div>`;
  let timer;
  $('#u-search').addEventListener('input', e => { clearTimeout(timer); timer = setTimeout(() => { U.search = e.target.value; U.page = 0; loadUsers(); }, 250); });
  [['role', 'u-role'], ['district', 'u-district'], ['school', 'u-school'], ['program', 'u-program'], ['status', 'u-status']].forEach(([k, id]) => $('#' + id).addEventListener('change', e => { U[k] = e.target.value; U.page = 0; loadUsers(); }));
  $('#u-new').addEventListener('click', () => userForm(null));
  await loadUsers();
}
async function loadUsers() {
  try {
    const rows = await rpc('app_admin_list_users', { p_search: U.search || null, p_role: U.role || null, p_district_id: U.district ? Number(U.district) : null,
      p_school_id: U.school ? Number(U.school) : null, p_program: U.program || null, p_status: U.status || null, p_limit: U.size, p_offset: U.page * U.size });
    U.rows = rows || []; U.total = U.rows.length ? Number(U.rows[0].total) : 0; drawUsers();
  } catch (e) { toast(friendly(e), 'err'); }
}
function drawUsers() {
  const t = $('#u-table'); if (!t) return;
  t.innerHTML = U.rows.length ? `<table><thead><tr><th>Username</th><th>Name</th><th>Role</th><th>District</th><th>School / program</th><th>Level</th><th>Status</th><th>Created</th><th>Last sign-in</th><th>Actions</th></tr></thead><tbody>
    ${U.rows.map(u => `<tr><td><strong>${esc(u.username)}</strong><br><span class="hint">${esc(u.email || '')}</span></td><td>${esc(u.display_name)}</td><td>${esc(ROLE_LABEL[u.role] || u.role)}</td><td>${esc(u.district_name || '-')}</td>
      <td>${u.school_name ? esc(u.school_name) + '<br>' + progBadges(u.programs) : '-'}</td><td>${esc(LEVEL_LABEL[u.education_level] || '-')}</td>
      <td><span class="badge ${u.active ? 'ok' : 'off'}">${u.active ? 'Active' : 'Disabled'}</span></td><td>${esc(fmt(u.created_at))}</td><td>${esc(fmt(u.last_sign_in_at))}</td>
      <td class="actions"><button class="btn btn-secondary btn-sm" data-edit="${esc(u.id)}">Edit</button><button class="btn btn-secondary btn-sm" data-pw="${esc(u.id)}">Reset password</button>
        <button class="btn ${u.active ? 'btn-danger' : 'btn-secondary'} btn-sm" data-toggle="${esc(u.id)}">${u.active ? 'Disable' : 'Enable'}</button></td></tr>`).join('')}</tbody></table>` : '<p class="empty">No users match.</p>';
  const from = U.total ? U.page * U.size + 1 : 0, to = Math.min(U.total, (U.page + 1) * U.size);
  $('#u-pager').innerHTML = `<span>Showing ${from} to ${to} of ${U.total}</span><span><button class="btn btn-secondary btn-sm" id="u-prev" ${U.page === 0 ? 'disabled' : ''}>Previous</button> <button class="btn btn-secondary btn-sm" id="u-next" ${to >= U.total ? 'disabled' : ''}>Next</button></span>`;
  $('#u-prev').onclick = () => { U.page--; loadUsers(); }; $('#u-next').onclick = () => { U.page++; loadUsers(); };
  t.querySelectorAll('[data-edit]').forEach(b => b.onclick = () => userForm(U.rows.find(u => u.id === b.dataset.edit)));
  t.querySelectorAll('[data-pw]').forEach(b => b.onclick = () => passwordForm(U.rows.find(u => u.id === b.dataset.pw)));
  t.querySelectorAll('[data-toggle]').forEach(b => b.onclick = () => toggleUser(U.rows.find(u => u.id === b.dataset.toggle)));
}
async function userForm(u) {
  const L = await lookups(), edit = !!u;
  const o = openModal(`<h3>${edit ? 'Edit user' : 'Create user'}</h3>
    <form id="uf" autocomplete="off">
      <div class="grid2"><div class="field"><label for="f-user">Username</label><input type="text" id="f-user" maxlength="40" value="${esc(u ? u.username : '')}" autocomplete="off"><div class="hint">3 to 40 characters: lowercase letters, numbers, dot, dash, underscore.</div></div>
      <div class="field"><label for="f-name">Display name</label><input type="text" id="f-name" maxlength="120" value="${esc(u ? u.display_name : '')}"></div></div>
      <div class="grid2"><div class="field"><label for="f-role">Role</label><select id="f-role">${Object.entries(ROLE_LABEL).map(([k, v]) => `<option value="${k}" ${u && u.role === k ? 'selected' : ''}>${v}</option>`).join('')}</select></div>
      <div class="field" id="g-status"><label>Account status</label><label class="checkrow"><input type="checkbox" id="f-active" ${!u || u.active ? 'checked' : ''}> Active</label></div></div>
      <div class="grid2"><div class="field" id="g-district"><label for="f-district">District</label><select id="f-district"><option value="">Choose a district</option>${L.districts.map(d => `<option value="${d.id}" ${u && u.district_id == d.id ? 'selected' : ''}>${esc(d.name)}</option>`).join('')}</select></div>
      <div class="field" id="g-level"><label for="f-level">Education level</label><select id="f-level"><option value="">Choose a level</option><option value="elementary" ${u && u.education_level === 'elementary' ? 'selected' : ''}>Elementary</option><option value="secondary" ${u && u.education_level === 'secondary' ? 'selected' : ''}>Secondary</option></select></div></div>
      <div class="field" id="g-school"><label for="f-school">School</label><select id="f-school"><option value="">Choose a school</option>${L.schools.filter(s => s.active || (u && u.school_id === s.id)).map(s => `<option value="${s.id}" ${u && u.school_id === s.id ? 'selected' : ''}>${esc(s.name)} - ${esc((L.districts.find(d => d.id === s.district_id) || {}).name || '')} (${esc(s.programs.map(p => PROGRAM_LABEL[p]).join(' + ') || 'no program')})</option>`).join('')}</select>
        <div class="hint" id="school-hint"></div></div>
      ${edit ? '' : `<div class="field"><label for="f-pass">Initial password (8 to 72 characters)</label><div style="display:flex;gap:8px"><input type="text" id="f-pass" maxlength="72" autocomplete="off"><button type="button" class="btn btn-secondary btn-sm" id="f-gen">Generate</button></div><div class="hint">The user signs in with this password as is. It is stored hashed and cannot be read back.</div></div>`}
      <div class="error" id="uf-error" role="alert"></div>
      <div class="actions"><button type="button" class="btn btn-secondary" id="uf-cancel">Cancel</button><button type="submit" class="btn" id="uf-save">${edit ? 'Save changes' : 'Create user'}</button></div>
    </form>`);
  const role = () => $('#f-role').value;
  const sync = () => {
    const r = role();
    $('#g-district').style.display = r === 'district_coordinator' ? '' : 'none'; $('#g-level').style.display = r === 'district_coordinator' ? '' : 'none';
    $('#g-school').style.display = r === 'school' ? '' : 'none'; $('#g-status').style.display = edit ? '' : 'none';
    $('#school-hint').textContent = r === 'school' ? 'The account can see and enter records for this school only, in its program(s).' : '';
  };
  $('#f-role').addEventListener('change', sync); sync();
  if ($('#f-gen')) $('#f-gen').addEventListener('click', () => { $('#f-pass').value = randomPassword(); });
  $('#uf-cancel').addEventListener('click', closeModal);
  $('#uf').addEventListener('submit', async ev => {
    ev.preventDefault();
    const err = $('#uf-error'), btn = $('#uf-save'), r = role();
    const a = { username: $('#f-user').value.trim().toLowerCase(), name: $('#f-name').value.trim(), district: r === 'district_coordinator' ? ($('#f-district').value || null) : null,
      level: r === 'district_coordinator' ? ($('#f-level').value || null) : null, school: r === 'school' ? ($('#f-school').value || null) : null, active: edit ? $('#f-active').checked : true };
    if (!/^[a-z0-9][a-z0-9._-]{2,39}$/.test(a.username)) { err.textContent = 'Username must be 3 to 40 characters: lowercase letters, numbers, dot, dash or underscore.'; return; }
    if (!a.name) { err.textContent = 'Enter a display name.'; return; }
    if (r === 'district_coordinator' && (!a.district || !a.level)) { err.textContent = 'A district coordinator needs a district and an education level.'; return; }
    if (r === 'school' && !a.school) { err.textContent = 'A school account needs a school.'; return; }
    const pw = edit ? null : $('#f-pass').value;
    if (!edit && (pw.length < 8 || pw.length > 72)) { err.textContent = 'The password must be 8 to 72 characters.'; return; }
    err.textContent = ''; setBusy(btn, true);
    try {
      if (edit) await rpc('app_admin_update_user', { p_id: u.id, p_username: a.username, p_display_name: a.name, p_role: r, p_district_id: a.district ? Number(a.district) : null, p_education_level: a.level, p_school_id: a.school ? Number(a.school) : null, p_active: a.active });
      else await rpc('app_admin_create_user', { p_username: a.username, p_display_name: a.name, p_role: r, p_district_id: a.district ? Number(a.district) : null, p_education_level: a.level, p_school_id: a.school ? Number(a.school) : null, p_password: pw });
      closeModal(); toast(edit ? 'User updated.' : `User "${a.username}" created.`); await loadUsers();
    } catch (e) { err.textContent = friendly(e); } finally { setBusy(btn, false); }
  });
}
function passwordForm(u) {
  openModal(`<h3>Reset password</h3><p>Set a new password for <strong>${esc(u.display_name)}</strong> (${esc(u.username)}). The current password cannot be viewed. The new one is stored hashed and is not recorded in any log.</p>
    <form id="pf" autocomplete="off"><div class="field"><label for="p-new">New password (8 to 72 characters)</label><div style="display:flex;gap:8px"><input type="text" id="p-new" maxlength="72" autocomplete="off"><button type="button" class="btn btn-secondary btn-sm" id="p-gen">Generate</button></div></div>
    <div class="error" id="pf-error" role="alert"></div><div id="pf-done"></div>
    <div class="actions"><button type="button" class="btn btn-secondary" id="pf-cancel">Close</button><button type="submit" class="btn" id="pf-save">Set password</button></div></form>`);
  $('#p-gen').addEventListener('click', () => { $('#p-new').value = randomPassword(); });
  $('#pf-cancel').addEventListener('click', closeModal);
  $('#pf').addEventListener('submit', async ev => {
    ev.preventDefault();
    const pw = $('#p-new').value, err = $('#pf-error'), btn = $('#pf-save');
    if (pw.length < 8 || pw.length > 72) { err.textContent = 'The password must be 8 to 72 characters.'; return; }
    err.textContent = ''; setBusy(btn, true);
    try {
      await rpc('app_admin_set_password', { p_id: u.id, p_password: pw });
      $('#pf-done').innerHTML = `<p class="badge ok" style="padding:8px 10px">Password set. Give it to ${esc(u.username)} privately; it cannot be shown again after you close this window.</p>`;
      toast('Password updated.'); btn.style.display = 'none';
    } catch (e) { err.textContent = friendly(e); setBusy(btn, false); }
  });
}
async function toggleUser(u) {
  const to = !u.active;
  if (!confirm(to ? `Enable ${u.username}? They will be able to sign in again.` : `Disable ${u.username}? They will lose access at once. Their assessment records are kept.`)) return;
  try {
    await rpc('app_admin_update_user', { p_id: u.id, p_username: u.username, p_display_name: u.display_name, p_role: u.role, p_district_id: u.district_id, p_education_level: u.education_level, p_school_id: u.school_id, p_active: to });
    toast(to ? 'User enabled.' : 'User disabled.'); await loadUsers();
  } catch (e) { toast(friendly(e), 'err'); }
}

/* ---------- Roles and permissions (read only) ---------- */
async function pRoles(page) {
  const st = await rpc('app_admin_user_stats'), by = st.by_role || {};
  const Y = '<span class="yes">Yes</span>', N = '<span class="no">No</span>';
  const rows = [
    ['View assessment data', 'All', 'All', 'Own district and education level', 'Own school and program only'],
    ['Create and edit assessment records', Y, Y, 'Own district and level', 'Own school and program'],
    ['Delete records (recoverable)', Y, Y, 'Own district and level', N],
    ['Restore deleted records, bulk delete', Y, Y, N, N],
    ['Download CSV export', Y, Y, N, N],
    ['Comparative notes', Y, Y, 'Own district and level', N],
    ['Settings & Branding, coordinators, signatories', Y, Y, N, N],
    ['Schools list and school accounts', Y, Y, N, N],
    ['Users, roles and password resets (/admin)', Y, N, N, N],
    ['Website content, images and settings (/admin)', Y, N, N, N],
    ['Audit logs (/admin)', Y, N, N, N]];
  page.innerHTML = `<div class="card"><h3>What each role can do</h3>
    <p class="hint">These permissions are enforced by the database (row level security and server functions), so they hold even if someone calls the data service directly. They are shown here for reference and are deliberately not editable: a toggle must never be able to weaken district, education-level, school or program restrictions. Roles are assigned to people under User Management.</p>
    <div class="scroll"><table class="matrix"><thead><tr><th>Capability</th><th>Administrator</th><th>Supervisor</th><th>District Coordinator</th><th>School Account</th></tr></thead><tbody>
    ${rows.map(r => `<tr>${r.map((c, i) => i === 0 ? `<td>${esc(c)}</td>` : `<td>${/^<span/.test(c) ? c : esc(c)}</td>`).join('')}</tr>`).join('')}</tbody></table></div></div>
    <div class="cards">${Object.keys(ROLE_LABEL).map(r => `<div class="stat"><strong>${by[r] || 0}</strong><span>${esc(ROLE_LABEL[r])} accounts</span></div>`).join('')}</div>`;
}

/* ---------- Website content ---------- */
const C = { saved: {}, group: null };
const contentError = (v, max) => {
  if (!v.trim()) return 'This text cannot be empty. Use "Reset to default" to go back to the original.';
  if (v.length > Math.min(max || 2000, 2000)) return `Too long (${Math.min(max || 2000, 2000)} characters at most).`;
  if (/[<>]/.test(v)) return 'Plain text only: the characters < and > are not allowed.';
  return '';
};
async function pContent(page) {
  const { data, error } = await sb().from('site_content').select('key, value, updated_at').range(0, 999);
  if (error) throw error;
  C.saved = {}; data.forEach(r => { C.saved[r.key] = r; });
  const groups = Array.from(new Set(REG.content.map(i => i.page)));
  if (!C.group || !groups.includes(C.group)) C.group = groups[0];
  const draw = () => {
    page.innerHTML = `<div class="card"><p class="hint">Edit the wording shown on the website. Changes appear as soon as you save; no deployment is needed. Text is plain text; line breaks are kept where the item allows them. Anything not listed here is not editable.</p>
      <div class="tabs" role="tablist">${groups.map(g => `<button class="tab" role="tab" aria-selected="${g === C.group}" data-group="${esc(g)}">${esc(g)}</button>`).join('')}</div>
      ${REG.content.filter(i => i.page === C.group).map(contentItem).join('')}</div>`;
    page.querySelectorAll('[data-group]').forEach(b => b.onclick = () => { if (!confirmLeave()) return; S.dirty = false; C.group = b.dataset.group; draw(); });
    page.querySelectorAll('.item').forEach(bindItem);
  };
  draw();
}
function contentItem(i) {
  const cur = C.saved[i.key] ? C.saved[i.key].value : i.def, edited = !!C.saved[i.key];
  return `<div class="item" data-key="${esc(i.key)}">
    <div class="meta"><div><strong>${esc(i.label)}</strong> <code>${esc(i.key)}</code></div><span class="badge ${edited ? 'warn' : ''}">${edited ? 'Edited' : 'Default'}</span></div>
    <textarea rows="${i.multiline ? 4 : 1}" maxlength="${Math.min(i.max || 2000, 2000)}" aria-label="${esc(i.label)}">${esc(cur)}</textarea>
    <div class="hint"><span class="count"></span> Default: ${esc(i.def)}</div><div class="error" role="alert"></div><div class="preview-host"></div>
    <div class="btns"><button class="btn btn-sm" data-do="save">Save</button><button class="btn btn-secondary btn-sm" data-do="cancel">Cancel changes</button>
      <button class="btn btn-secondary btn-sm" data-do="preview">Preview</button>${edited ? '<button class="btn btn-danger btn-sm" data-do="reset">Reset to default</button>' : ''}
      <button class="btn btn-secondary btn-sm" data-do="history">History</button></div></div>`;
}
function bindItem(el) {
  const i = REG.content.find(x => x.key === el.dataset.key), ta = el.querySelector('textarea'), err = el.querySelector('.error');
  const base = () => C.saved[i.key] ? C.saved[i.key].value : i.def;
  const count = () => { el.querySelector('.count').textContent = `${ta.value.length}/${Math.min(i.max || 2000, 2000)} characters.`; S.dirty = Array.from(document.querySelectorAll('.item textarea')).some(t => t.value !== (C.saved[t.closest('.item').dataset.key] ? C.saved[t.closest('.item').dataset.key].value : REG.content.find(x => x.key === t.closest('.item').dataset.key).def)); };
  ta.addEventListener('input', count); count();
  el.addEventListener('click', async e => {
    const b = e.target.closest('[data-do]'); if (!b) return;
    const act = b.dataset.do;
    if (act === 'cancel') { ta.value = base(); err.textContent = ''; el.querySelector('.preview-host').innerHTML = ''; count(); }
    if (act === 'preview') { const m = contentError(ta.value, i.max); err.textContent = m; el.querySelector('.preview-host').innerHTML = m ? '' : `<div class="preview">${esc(ta.value)}</div>`; }
    if (act === 'save') {
      const m = contentError(ta.value, i.max); err.textContent = m; if (m) return;
      setBusy(b, true);
      try { await rpc('app_admin_save_content', { p_key: i.key, p_value: ta.value }); toast('Saved. The website now shows this text.'); S.dirty = false; await pContent($('#page')); }
      catch (x) { err.textContent = friendly(x); setBusy(b, false); }
    }
    if (act === 'reset') {
      if (!confirm('Go back to the original wording for this item?')) return;
      try { await rpc('app_admin_reset_content', { p_key: i.key }); toast('Reset to the default text.'); S.dirty = false; await pContent($('#page')); } catch (x) { err.textContent = friendly(x); }
    }
    if (act === 'history') history_(i);
  });
}
async function history_(i) {
  const { data, error } = await sb().from('site_content_versions').select('id, old_value, new_value, changed_at').eq('key', i.key).order('id', { ascending: false }).limit(20);
  if (error) { toast(friendly(error), 'err'); return; }
  const o = openModal(`<h3>History: ${esc(i.label)}</h3>${data.length ? data.map(v => `<div class="item"><div class="meta"><span>${esc(fmt(v.changed_at))}</span>
    <button class="btn btn-secondary btn-sm" data-restore="${v.id}">Restore the earlier text</button></div>
    <div class="hint">Before:</div><div class="preview">${esc(v.old_value === null ? '(default text)' : v.old_value)}</div><div class="hint">After:</div><div class="preview">${esc(v.new_value === null ? '(reset to default)' : v.new_value)}</div></div>`).join('') : '<p class="empty">No changes recorded yet.</p>'}
    <div class="actions"><button class="btn btn-secondary" id="h-close">Close</button></div>`, true);
  $('#h-close').addEventListener('click', closeModal);
  o.querySelectorAll('[data-restore]').forEach(b => b.addEventListener('click', async () => {
    if (!confirm('Restore the earlier text? The current text stays in the history.')) return;
    try { await rpc('app_admin_restore_content', { p_version_id: Number(b.dataset.restore) }); closeModal(); toast('Restored.'); S.dirty = false; await pContent($('#page')); } catch (x) { toast(friendly(x), 'err'); }
  }));
}

/* ---------- Image and media library ---------- */
const mediaUrl = p => `${CFG.supabaseUrl}/storage/v1/object/public/site-media/${encodeURIComponent(p)}`;
const MIME_EXT = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp' };
const MAX_BYTES = 2 * 1024 * 1024;
async function pMedia(page) {
  const [m, s] = await Promise.all([sb().from('site_media').select('id, path, original_name, mime, size_bytes, alt_text, uploaded_at').order('uploaded_at', { ascending: false }).range(0, 999),
    sb().from('site_media_slots').select('slot, media_id')]);
  if (m.error) throw m.error; if (s.error) throw s.error;
  const byId = {}; m.data.forEach(x => { byId[x.id] = x; });
  const slotOf = {}; s.data.forEach(x => { (slotOf[x.media_id] = slotOf[x.media_id] || []).push(x.slot); });
  const label = slot => (REG.slots.find(x => x.slot === slot) || {}).label || slot;
  page.innerHTML = `
  <div class="card"><div class="toolbar"><div class="grow"><h3 style="margin:0">Image positions</h3><p class="hint" style="margin:2px 0 0">Choose which uploaded image appears in each position. Empty positions keep the built-in look.</p></div><div><button class="btn" id="m-upload">Upload an image</button></div></div>
    <div class="slots">${REG.slots.map(sl => { const cur = s.data.find(x => x.slot === sl.slot), img = cur ? byId[cur.media_id] : null; return `<div class="tile">
      <strong>${esc(sl.label)}</strong><div class="hint">${esc(sl.where)}${sl.note ? ' - ' + esc(sl.note) : ''}</div>
      <div class="thumb ${img ? '' : 'empty'}">${img ? `<img src="${esc(mediaUrl(img.path))}" alt="${esc(img.alt_text)}">` : 'No image'}</div>
      <div class="hint">${img ? esc(img.original_name) : ''}</div>
      <div style="display:flex;gap:6px;flex-wrap:wrap"><button class="btn btn-secondary btn-sm" data-replace="${esc(sl.slot)}">${img ? 'Replace' : 'Choose / upload'}</button>${img ? `<button class="btn btn-danger btn-sm" data-clear="${esc(sl.slot)}">Remove from page</button>` : ''}</div></div>`; }).join('')}</div></div>
  <div class="card"><h3>Library (${m.data.length})</h3>${m.data.length ? `<div class="library">${m.data.map(x => `<div class="tile"><div class="thumb"><img src="${esc(mediaUrl(x.path))}" alt="${esc(x.alt_text)}" loading="lazy"></div>
    <div><strong>${esc(x.original_name)}</strong><div class="hint">${esc(fmt(x.uploaded_at))} - ${Math.round(x.size_bytes / 1024)} KB</div><div class="hint">Used in: ${slotOf[x.id] ? esc(slotOf[x.id].map(label).join(', ')) : 'not in use'}</div></div>
    <div class="field" style="margin:0"><label>Description (alternative text)</label><input type="text" maxlength="200" value="${esc(x.alt_text)}" data-alt="${esc(x.id)}"></div>
    <div style="display:flex;gap:6px;flex-wrap:wrap"><button class="btn btn-secondary btn-sm" data-savealt="${esc(x.id)}">Save description</button><button class="btn btn-danger btn-sm" data-del="${esc(x.id)}" ${slotOf[x.id] ? 'disabled title="In use: replace or remove it from its position first"' : ''}>Delete</button></div></div>`).join('')}</div>` : '<p class="empty">No images uploaded yet.</p>'}</div>`;
  $('#m-upload').addEventListener('click', () => uploadForm(null, m.data));
  page.querySelectorAll('[data-replace]').forEach(b => b.onclick = () => uploadForm(b.dataset.replace, m.data));
  page.querySelectorAll('[data-clear]').forEach(b => b.onclick = async () => { if (!confirm('Remove this image from the page? The file stays in the library.')) return; try { await rpc('app_admin_assign_media', { p_slot: b.dataset.clear, p_media_id: null }); toast('Removed from the page.'); pMedia(page); } catch (e) { toast(friendly(e), 'err'); } });
  page.querySelectorAll('[data-savealt]').forEach(b => b.onclick = async () => { const v = page.querySelector(`[data-alt="${b.dataset.savealt}"]`).value; try { await rpc('app_admin_update_media', { p_id: b.dataset.savealt, p_alt: v }); toast('Description saved.'); } catch (e) { toast(friendly(e), 'err'); } });
  page.querySelectorAll('[data-del]').forEach(b => b.onclick = async () => {
    if (!confirm('Delete this image permanently?')) return;
    try { const path = await rpc('app_admin_delete_media', { p_id: b.dataset.del }); const r = await sb().storage.from('site-media').remove([path]); if (r.error) toast('Record removed; the file could not be deleted: ' + friendly(r.error), 'info'); else toast('Image deleted.'); pMedia(page); } catch (e) { toast(friendly(e), 'err'); }
  });
}
function imageProblem(file) {
  if (!file) return 'Choose an image file.';
  if (!MIME_EXT[file.type]) return 'Only PNG, JPEG or WebP images are allowed.';
  if (file.size > MAX_BYTES) return 'The image must be 2 MB or smaller.';
  if (file.size < 1) return 'The file is empty.';
  return '';
}
function uploadForm(slot, library) {
  const slotInfo = slot ? REG.slots.find(x => x.slot === slot) : null;
  const o = openModal(`<h3>${slotInfo ? 'Image for: ' + esc(slotInfo.label) : 'Upload an image'}</h3>
    <form id="mf">
      ${library.length && slot ? `<div class="field"><label for="m-existing">Use an image already in the library</label><select id="m-existing"><option value="">Choose...</option>${library.map(x => `<option value="${esc(x.id)}">${esc(x.original_name)}</option>`).join('')}</select></div><p class="hint">Or upload a new one:</p>` : ''}
      <div class="field"><label for="m-file">Image (PNG, JPEG or WebP, up to 2 MB)</label><input type="file" id="m-file" accept="image/png,image/jpeg,image/webp"></div>
      <div class="thumb empty" id="m-prev">Preview appears here</div>
      <div class="field" style="margin-top:12px"><label for="m-alt">Description for accessibility (alternative text)</label><input type="text" id="m-alt" maxlength="200"></div>
      ${slot ? '' : `<div class="field"><label for="m-slot">Use it in (optional)</label><select id="m-slot"><option value="">Just add to the library</option>${REG.slots.map(x => `<option value="${esc(x.slot)}">${esc(x.label)}</option>`).join('')}</select></div>`}
      <div class="error" id="mf-error" role="alert"></div>
      <div class="actions"><button type="button" class="btn btn-secondary" id="mf-cancel">Cancel</button><button type="submit" class="btn" id="mf-save">Save</button></div></form>`, true);
  $('#mf-cancel').addEventListener('click', closeModal);
  $('#m-file').addEventListener('change', e => {
    const f = e.target.files[0], err = $('#mf-error'), prev = $('#m-prev'); err.textContent = ''; prev.className = 'thumb empty'; prev.textContent = 'Preview appears here';
    if (!f) return; const p = imageProblem(f); if (p) { err.textContent = p; e.target.value = ''; return; }
    const url = URL.createObjectURL(f), img = new Image();
    img.onload = () => { prev.className = 'thumb'; prev.innerHTML = ''; prev.appendChild(img); };
    img.onerror = () => { err.textContent = 'That file is not a readable image.'; e.target.value = ''; URL.revokeObjectURL(url); };
    img.src = url; img.alt = 'Preview';
  });
  $('#mf').addEventListener('submit', async ev => {
    ev.preventDefault();
    const err = $('#mf-error'), btn = $('#mf-save'), file = $('#m-file').files[0], existing = $('#m-existing') ? $('#m-existing').value : '', target = slot || ($('#m-slot') ? $('#m-slot').value : '');
    if (!file && !existing) { err.textContent = 'Choose an image to upload or pick one from the library.'; return; }
    if (file) { const p = imageProblem(file); if (p) { err.textContent = p; return; } }
    err.textContent = ''; setBusy(btn, true);
    let uploaded = null;
    try {
      let mediaId = existing || null;
      if (file) {
        const path = `${crypto.randomUUID()}.${MIME_EXT[file.type]}`;
        const up = await sb().storage.from('site-media').upload(path, file, { contentType: file.type, upsert: false, cacheControl: '31536000' });
        if (up.error) throw up.error; uploaded = path;
        mediaId = await rpc('app_admin_register_media', { p_path: path, p_name: file.name, p_mime: file.type, p_size: file.size, p_alt: $('#m-alt').value });
        uploaded = null;
      }
      if (target) await rpc('app_admin_assign_media', { p_slot: target, p_media_id: mediaId });
      closeModal(); toast(target ? 'Saved. The image is now in use.' : 'Image added to the library.'); await pMedia($('#page'));
    } catch (e) {
      if (uploaded) { try { await sb().storage.from('site-media').remove([uploaded]); } catch (_) { /* orphan file is harmless */ } }
      err.textContent = friendly(e); setBusy(btn, false);
    }
  });
}

/* ---------- Website settings ---------- */
async function pSettings(page) {
  const { data, error } = await sb().from('site_settings').select('key, value');
  if (error) throw error;
  const V = {}; data.forEach(r => { V[r.key] = r.value; });
  const ann = V.announcement || { enabled: false, text: '', level: 'info' }, ct = V.contact || { email: '', phone: '', address: '' };
  page.innerHTML = `
  <div class="card"><h3>Website title and organization</h3><form novalidate data-setting="titles"><div class="grid2">
    <div class="field"><label for="s-title">Website title (browser tab)</label><input type="text" id="s-title" maxlength="120" value="${esc(V['site.title'] || '')}" placeholder="DepEd SDO Division Assessment System"></div>
    <div class="field"><label for="s-org">Organization name (menu header)</label><input type="text" id="s-org" maxlength="120" value="${esc(V['org.name'] || '')}" placeholder="SDO Davao del Norte"></div></div>
    <div class="hint">Leave blank to keep the built-in wording.</div><div class="error" role="alert"></div><button class="btn" type="submit">Save</button></form></div>
  <div class="card"><h3>Announcement banner</h3><form novalidate data-setting="announcement">
    <div class="field"><label class="checkrow"><input type="checkbox" id="a-on" ${ann.enabled ? 'checked' : ''}> Show the banner (login page and every screen)</label></div>
    <div class="grid2"><div class="field"><label for="a-level">Style</label><select id="a-level"><option value="info" ${ann.level === 'info' ? 'selected' : ''}>Information</option><option value="warning" ${ann.level === 'warning' ? 'selected' : ''}>Warning</option></select></div></div>
    <div class="field"><label for="a-text">Message (plain text, up to 300 characters)</label><textarea id="a-text" maxlength="300">${esc(ann.text)}</textarea></div>
    <div class="error" role="alert"></div><button class="btn" type="submit">Save</button></form></div>
  <div class="card"><h3>What people see first</h3><form novalidate data-setting="landing"><div class="grid2">
    <div class="field"><label for="d-view">Screen shown after sign-in</label><select id="d-view">${Object.entries(REG.views).map(([k, v]) => `<option value="${k}" ${(V.default_view || 'division') === k ? 'selected' : ''}>${esc(v)}</option>`).join('')}</select><div class="hint">School accounts always start on the Dashboard.</div></div>
    <div class="field"><label for="d-sy">School year shown first</label><select id="d-sy"><option value="ALL" ${(V.default_sy || 'ALL') === 'ALL' ? 'selected' : ''}>All school years</option>${REG.schoolYears.map(y => `<option value="${y}" ${V.default_sy === y ? 'selected' : ''}>SY ${y}</option>`).join('')}</select></div></div>
    <div class="error" role="alert"></div><button class="btn" type="submit">Save</button></form></div>
  <div class="card"><h3>Public contact information</h3><form novalidate data-setting="contact"><div class="grid2">
    <div class="field"><label for="c-email">Email</label><input type="email" id="c-email" maxlength="120" value="${esc(ct.email)}"></div>
    <div class="field"><label for="c-phone">Phone</label><input type="text" id="c-phone" maxlength="40" value="${esc(ct.phone)}"></div></div>
    <div class="field"><label for="c-addr">Address</label><input type="text" id="c-addr" maxlength="200" value="${esc(ct.address)}"></div>
    <div class="hint">Shown under the sign-in form when filled in.</div><div class="error" role="alert"></div><button class="btn" type="submit">Save</button></form></div>`;
  page.querySelectorAll('form[data-setting]').forEach(f => f.addEventListener('submit', async ev => {
    ev.preventDefault();
    const err = f.querySelector('.error'), btn = f.querySelector('button[type=submit]'); err.textContent = ''; setBusy(btn, true);
    try {
      const kind = f.dataset.setting;
      if (kind === 'titles') {
        const t = $('#s-title').value.trim(), g = $('#s-org').value.trim();
        if (t) await rpc('app_admin_save_setting', { p_key: 'site.title', p_value: t }); else await clearSetting('site.title');
        if (g) await rpc('app_admin_save_setting', { p_key: 'org.name', p_value: g }); else await clearSetting('org.name');
      } else if (kind === 'announcement') {
        await rpc('app_admin_save_setting', { p_key: 'announcement', p_value: { enabled: $('#a-on').checked, text: $('#a-text').value, level: $('#a-level').value } });
      } else if (kind === 'landing') {
        await rpc('app_admin_save_setting', { p_key: 'default_view', p_value: $('#d-view').value });
        await rpc('app_admin_save_setting', { p_key: 'default_sy', p_value: $('#d-sy').value });
      } else if (kind === 'contact') {
        await rpc('app_admin_save_setting', { p_key: 'contact', p_value: { email: $('#c-email').value, phone: $('#c-phone').value, address: $('#c-addr').value } });
      }
      toast('Settings saved.');
    } catch (e) { err.textContent = friendly(e); } finally { setBusy(btn, false); }
  }));
}
const clearSetting = key => rpc('app_admin_clear_setting', { p_key: key });

/* ---------- Audit logs ---------- */
const A = { tab: 'activity', action: '', outcome: '', page: 0, size: 25 };
async function pAudit(page) {
  const draw = async () => {
    const isAct = A.tab === 'activity';
    const rows = isAct ? await rpc('app_admin_activity', { p_action: A.action || null, p_outcome: A.outcome || null, p_limit: A.size, p_offset: A.page * A.size })
      : await rpc('app_admin_data_changes', { p_limit: A.size, p_offset: A.page * A.size });
    const total = rows.length ? Number(rows[0].total) : 0, from = total ? A.page * A.size + 1 : 0, to = Math.min(total, (A.page + 1) * A.size);
    page.innerHTML = `<div class="card"><div class="tabs" role="tablist"><button class="tab" role="tab" aria-selected="${isAct}" data-tab="activity">Administrative actions</button><button class="tab" role="tab" aria-selected="${!isAct}" data-tab="data">Data changes</button></div>
      ${isAct ? `<div class="toolbar"><div><label for="a-action">Action</label><select id="a-action"><option value="">All actions</option>${['admin.', 'user.', 'content.', 'settings.', 'media.'].map(x => `<option value="${x}" ${A.action === x ? 'selected' : ''}>${x.replace('.', '')}</option>`).join('')}</select></div>
        <div><label for="a-outcome">Outcome</label><select id="a-outcome"><option value="">Any</option><option value="success" ${A.outcome === 'success' ? 'selected' : ''}>Success</option><option value="denied" ${A.outcome === 'denied' ? 'selected' : ''}>Denied</option><option value="failure" ${A.outcome === 'failure' ? 'selected' : ''}>Failure</option></select></div></div>` : '<p class="hint">Changes to assessment data, schools, settings and content, recorded automatically (summary only).</p>'}
      <div class="scroll">${rows.length ? (isAct ? `<table><thead><tr><th>When</th><th>Administrator</th><th>Action</th><th>Resource</th><th>Outcome</th><th>Details</th></tr></thead><tbody>${rows.map(r => `<tr><td>${esc(fmt(r.at))}</td><td>${esc(r.actor_name || '-')}</td><td>${esc(r.action)}</td><td>${esc(r.resource || '')} ${esc(r.resource_id || '')}</td><td>${outcomeBadge(r.outcome)}</td><td class="hint">${esc(detailText(r.details))}</td></tr>`).join('')}</tbody></table>`
        : `<table><thead><tr><th>When</th><th>By</th><th>Table</th><th>Action</th><th>Record</th></tr></thead><tbody>${rows.map(r => `<tr><td>${esc(fmt(r.at))}</td><td>${esc(r.actor_name || '-')}</td><td>${esc(r.table_name)}</td><td>${esc(r.action)}</td><td>${esc(r.row_id || '')}</td></tr>`).join('')}</tbody></table>`) : '<p class="empty">Nothing recorded.</p>'}</div>
      <div class="pager"><span>Showing ${from} to ${to} of ${total}</span><span><button class="btn btn-secondary btn-sm" id="g-prev" ${A.page === 0 ? 'disabled' : ''}>Previous</button> <button class="btn btn-secondary btn-sm" id="g-next" ${to >= total ? 'disabled' : ''}>Next</button></span></div></div>`;
    page.querySelectorAll('[data-tab]').forEach(b => b.onclick = () => { A.tab = b.dataset.tab; A.page = 0; draw(); });
    if ($('#a-action')) { $('#a-action').onchange = e => { A.action = e.target.value; A.page = 0; draw(); }; $('#a-outcome').onchange = e => { A.outcome = e.target.value; A.page = 0; draw(); }; }
    $('#g-prev').onclick = () => { A.page--; draw(); }; $('#g-next').onclick = () => { A.page++; draw(); };
  };
  await draw();
}
function detailText(d) {
  if (!d || typeof d !== 'object') return '';
  return Object.entries(d).map(([k, v]) => `${k}: ${v && typeof v === 'object' ? JSON.stringify(v) : v}`).join('; ');
}

/* ---------- Account settings ---------- */
async function pAccount(page) {
  page.innerHTML = `<div class="card"><h3>Your account</h3><dl class="kv"><dt>Name</dt><dd>${esc(S.me.name)}</dd><dt>Username</dt><dd>${esc(S.me.username)}</dd><dt>Role</dt><dd>Administrator</dd>
      <dt>Session</dt><dd>You are signed out automatically after 30 minutes without activity.</dd></dl></div>
    <div class="card"><h3>Change your password (optional)</h3><p class="hint">At least 10 characters, with a letter and a number. Your current password is checked first.</p>
      <form id="cp" autocomplete="off" style="max-width:420px"><div class="field"><label for="cp-old">Current password</label><input type="password" id="cp-old" autocomplete="current-password"></div>
      <div class="field"><label for="cp-new">New password</label><input type="password" id="cp-new" autocomplete="new-password"></div>
      <div class="field"><label for="cp-conf">Confirm new password</label><input type="password" id="cp-conf" autocomplete="new-password"></div>
      <div class="error" id="cp-error" role="alert"></div><button class="btn" type="submit" id="cp-save">Change password</button></form></div>
    <div class="card"><button class="btn btn-secondary" data-act="logout">Logout</button></div>`;
  $('#cp').addEventListener('submit', async ev => {
    ev.preventDefault();
    const err = $('#cp-error'), btn = $('#cp-save'), o = $('#cp-old').value, n = $('#cp-new').value;
    if (n.length < 10 || !/[A-Za-z]/.test(n) || !/[0-9]/.test(n)) { err.textContent = 'Use at least 10 characters, with a letter and a number.'; return; }
    if (n !== $('#cp-conf').value) { err.textContent = 'The two new passwords do not match.'; return; }
    if (n === o) { err.textContent = 'Choose a password you have not used before.'; return; }
    err.textContent = ''; setBusy(btn, true);
    try {
      const { data: { session } } = await sb().auth.getSession();
      const chk = await sb().auth.signInWithPassword({ email: session.user.email, password: o });
      if (chk.error) { err.textContent = chk.error.status === 400 ? 'Your current password is incorrect.' : friendly(chk.error); return; }
      const up = await sb().auth.updateUser({ password: n });
      if (up.error) { err.textContent = friendly(up.error); return; }
      try { await rpc('app_admin_log_event', { p_action: 'password_changed_self' }); } catch (_) { /* best effort */ }
      $('#cp').reset(); toast('Your password was changed.');
    } catch (e) { err.textContent = friendly(e); } finally { setBusy(btn, false); }
  });
}

/* ---------- start ---------- */
async function boot() {
  if (!CFG.supabaseUrl || !CFG.supabasePublishableKey) { $('#app').innerHTML = '<p class="boot">The site is not configured (config.js).</p>'; return; }
  try {
    const { data: { session } } = await sb().auth.getSession();
    if (!session) { loginView(); bindLogin(); return; }
    await enter(false);
  } catch (e) { loginView(friendly(e)); bindLogin(); }
}
sb().auth.onAuthStateChange(ev => { if (ev === 'SIGNED_OUT' && S.me) { S.me = null; loginView(); bindLogin(); } });
boot();
})();
