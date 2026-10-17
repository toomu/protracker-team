// Demo mode (index.html?demo): a stand-in for the Supabase client that keeps everything in this browser.
// Sign in with any email and the code 123456; owner@demo.test is the owner. Each tab keeps its own sign-in,
// so you can be the owner in one tab and someone else in another. Nothing leaves the browser.
(() => {
  try { sessionStorage.length; } catch { return; }
  const OWNER = "owner@demo.test";
  const DB_KEY = "team.demo.db", SESSION_KEY = "team.demo.session";
  const load = () => { try { return JSON.parse(localStorage.getItem(DB_KEY)) || { rows: [], users: {} }; } catch { return { rows: [], users: {} }; } };
  const save = (db) => { localStorage.setItem(DB_KEY, JSON.stringify(db)); };
  let session = (() => { try { return JSON.parse(sessionStorage.getItem(SESSION_KEY)); } catch { return null; } })();
  const authListeners = [], changeListeners = [];
  const emitAuth = () => authListeners.forEach(cb => cb(session ? "SIGNED_IN" : "SIGNED_OUT", session));
  // Other tabs' changes arrive through the storage event, like the real app's live updates.
  window.addEventListener("storage", (e) => { if (e.key === DB_KEY) changeListeners.forEach(cb => cb()); });
  const meEmail = () => session && session.user.email;
  const isOwner = () => meEmail() === OWNER;
  const visible = (r) => isOwner() || r.assignee_email === meEmail();
  const ok = (data) => Promise.resolve({ data, error: null });
  const bad = (message) => Promise.resolve({ data: null, error: { message } });
  const uuid = () => (crypto.randomUUID ? crypto.randomUUID()
    : "10000000-1000-4000-8000-100000000000".replace(/[018]/g, c => (c ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> c / 4).toString(16)));

  function from() {
    const q = { op: "select", filters: [], payload: null };
    const run = () => {
      if (!session) return bad("not signed in");
      const db = load();
      const match = (r) => visible(r) && q.filters.every(([c, v, kind]) => kind === "in" ? v.includes(r[c]) : r[c] === v);
      if (q.op === "select") return ok(db.rows.filter(match).map(r => ({ ...r })));
      if (q.op === "insert") {
        const list = Array.isArray(q.payload) ? q.payload : [q.payload];
        for (const r of list) {
          if (!isOwner() && (r.assignee_email !== meEmail() || r.source_id)) return bad("new row violates row-level security policy");
          if (r.source_id && db.rows.some(x => x.assignee_email === r.assignee_email && x.source_id === r.source_id)) return bad("duplicate key value");
        }
        list.forEach(r => db.rows.push({ done: false, completed_at: null, parent_id: null, sort: 0, source_id: null, created_at: new Date().toISOString(), ...r }));
        save(db);
        return ok(null);
      }
      if (q.op === "update") {
        if (!isOwner() && "assignee_email" in q.payload && q.payload.assignee_email !== meEmail()) return bad("new row violates row-level security policy");
        db.rows = db.rows.map(r => match(r) ? { ...r, ...q.payload } : r);
        save(db);
        return ok(null);
      }
      if (q.op === "delete") {
        const gone = new Set(db.rows.filter(r => match(r) && (isOwner() || (!r.source_id && r.created_by === session.user.id))).map(r => r.id));
        db.rows = db.rows.filter(r => !gone.has(r.id)).map(r => gone.has(r.parent_id) ? { ...r, parent_id: null } : r);
        save(db);
        return ok(null);
      }
      return bad("unsupported");
    };
    const b = {
      select() { return b; },
      insert(p) { q.op = "insert"; q.payload = p; return b; },
      update(p) { q.op = "update"; q.payload = p; return b; },
      delete() { q.op = "delete"; return b; },
      eq(c, v) { q.filters.push([c, v]); return b; },
      in(c, v) { q.filters.push([c, v, "in"]); return b; },
      then(res, rej) { return run().then(res, rej); },
    };
    return b;
  }

  window.TEAM_CLIENT = {
    demo: { owner: OWNER, code: "123456" },
    auth: {
      getSession: () => ok({ session }),
      onAuthStateChange: (cb) => { authListeners.push(cb); return { data: { subscription: { unsubscribe() {} } } }; },
      signInWithOtp: () => ok({}),
      verifyOtp: ({ email, token }) => {
        if (token !== "123456") return bad("In demo mode the code is 123456");
        const db = load();
        db.users[email] = db.users[email] || uuid();
        save(db);
        session = { user: { id: db.users[email], email } };
        sessionStorage.setItem(SESSION_KEY, JSON.stringify(session));
        emitAuth();
        return ok({ session });
      },
      signOut: () => { session = null; sessionStorage.removeItem(SESSION_KEY); emitAuth(); return ok(null); },
    },
    rpc: (name) => ok(name === "is_admin" && isOwner()),
    from,
    channel: () => ({ on(_e, _f, cb) { changeListeners.push(cb); return this; }, subscribe() { return this; } }),
    removeChannel() {},
  };
})();
