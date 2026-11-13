// Runs every app check. Usage:  node tests/run-all.js
// Each check starts the real app code with fake data; nothing touches the real database.
const { start, wait } = require("./harness");

const UID = "u1";
const T1 = Date.parse("2026-11-01T10:00:00Z"), T2 = Date.parse("2026-11-05T10:00:00Z"), T3 = Date.parse("2026-11-08T10:00:00Z");
const iso = (t) => new Date(t).toISOString();
const profile = (role) => ({ id: UID, role, class_id: "c1", name: "Maria", joined_at: iso(T1), last_seen: iso(T1) });
const klass = (extra) => Object.assign({ id: "c1", name: "Test", meet: "", week: 5, ahead: true, message: "", material: "disciple", join_code: "X", teacher_id: "t1" }, extra);
const student = (extra) => Object.assign({ profiles: [profile("student")], classes: [klass()], progress: [{ user_id: UID, done: [], verses: [], tasks: {} }] }, extra);
const teacher = (classExtra) => ({ profiles: [profile("teacher")], classes: [klass(classExtra)] });

let failed = 0;
const results = [];
function check(name, ok, detail) { results.push((ok ? "  ok    " : "  FAIL  ") + name + (ok || !detail ? "" : "  (" + detail + ")")); if (!ok) failed++; }

const tests = {
  async "Two devices: a phone with unsent changes merges instead of overwriting"() {
    const server = {
      profiles: [profile("student")], classes: [klass()],
      progress: [{ user_id: UID, done: [1, 5, 1003], verses: [5], tasks: { "5": [true, false] } }],
      journal: [{ user_id: UID, lesson: 2, body: "laptop newer", shared: true, updated_at: iso(T3) },
                { user_id: UID, lesson: 3, body: "laptop only", shared: false, updated_at: iso(T2) }],
      prayers: [{ id: "P1", user_id: UID, class_id: "c1", body: "both", vis: "t", answered: false, created_at: iso(T1) },
                { id: "P2", user_id: UID, class_id: "c1", body: "added on laptop", vis: "t", answered: false, created_at: iso(T2) },
                { id: "P3", user_id: UID, class_id: "c1", body: "deleted on phone", vis: "t", answered: false, created_at: iso(T1) }],
      prep: [{ user_id: UID, lesson: 4, body: "laptop prep newer", updated_at: iso(T3) }]
    };
    const local = {
      ["dc_dirty_" + UID]: "1",
      ["dc_me_" + UID]: JSON.stringify({ name: "Maria", joined: T1, last: T1, done: [1, 2], verses: [], tasks: { "5": [false, true], "2": [true] },
        prayers: [{ id: "P1", t: "both", ts: T1, vis: "t", a: false }, { id: "P4", t: "new on phone", ts: T2, vis: "t", a: false }],
        pdel: ["P3"], sharedJ: {}, sharedEver: false, pEver: true }),
      ["dc_j_" + UID]: JSON.stringify({ entries: { "1": { t: "phone only", ts: T2 }, "2": { t: "phone older", ts: T1 } } }),
      ["dc_p_" + UID]: JSON.stringify({ "4": { t: "phone prep older", ts: T1 }, "6": { t: "phone prep only", ts: T2 } })
    };
    const app = start({ server, local });
    await wait(2500);
    const last = (t, op) => app.writes.filter((w) => w.table === t && w.op === op).pop();
    const prog = last("progress", "upsert"), pUp = last("prayers", "upsert"), pDel = last("prayers", "delete");
    const j = [].concat(...app.writes.filter((w) => w.table === "journal" && w.op === "upsert").map((w) => w.payload)).map((r) => r.lesson).sort();
    const p = [].concat(...app.writes.filter((w) => w.table === "prep" && w.op === "upsert").map((w) => w.payload)).map((r) => r.lesson).sort();
    check("lessons done from both devices kept (and other materials untouched)", prog && JSON.stringify(prog.payload.done.slice().sort((a, b) => a - b)) === "[1,2,5,1003]");
    check("verse learned on the laptop kept", prog && prog.payload.verses.includes(5));
    check("tasks combined", prog && JSON.stringify(prog.payload.tasks["5"]) === "[true,true]" && JSON.stringify(prog.payload.tasks["2"]) === "[true]");
    check("prayers from both devices kept", pUp && JSON.stringify(pUp.payload.map((x) => x.id).sort()) === '["P1","P2","P4"]');
    check("prayer deleted on the phone is deleted", pDel && JSON.stringify(pDel.filters[0][1]) === '["P3"]');
    check("newer journal entry on the laptop not overwritten", JSON.stringify(j) === "[1]", JSON.stringify(j));
    check("newer prep answer on the laptop not overwritten", JSON.stringify(p) === "[6]", JSON.stringify(p));
    check("unsent flag cleared afterwards", !app.ls.has("dc_dirty_" + UID));
  },

  async "Lessons: first visit opens a lesson with Bible text"() {
    const app = start({ server: student(), hash: "sl1" });
    await wait(1500);
    check("lesson 1 shown", /<h1 class="lh1">Where will you spend eternity\?/.test(app.page()));
    check("verse text shown", (app.page().match(/class="vtext"/g) || []).length > 0);
    check("only this class's lessons downloaded", JSON.stringify(app.fetched.slice().sort()) === '["data/bible.json","data/mat-disciple.json"]', JSON.stringify(app.fetched));
  },

  async "Lessons: returning user (lessons already saved on the phone)"() {
    const app = start({ server: student(), hash: "sl1", local: { dc_lastmat: "disciple" } });
    await wait(1500);
    check("lesson 1 shown (this was the live bug)", /<h1 class="lh1">Where will you spend eternity\?/.test(app.page()));
  },

  async "Lessons: a Preparatory Lesson class downloads only its own lessons"() {
    const app = start({ server: teacher({ material: "prep" }), hash: "tset" });
    await wait(1500);
    check("class settings shown", app.page().includes("Class settings"));
    check("only the 13 KB Preparatory lessons downloaded", !app.fetched.includes("data/mat-disciple.json") && app.fetched.includes("data/mat-prep.json"), JSON.stringify(app.fetched));
  },

  async "Lessons: no connection on a phone that never got them"() {
    const app = start({ server: teacher({ material: "prep" }), hash: "tset", blockFetch: /mat-/ });
    await wait(1500);
    check("clear message with a retry button", app.page().includes("The lessons could not load") && app.page().includes('data-act="retrylessons"'));
    check("retry fetches the class's own lessons", app.fetched.filter((f) => f.includes("mat-")).every((f) => f === "data/mat-prep.json"), JSON.stringify(app.fetched));
  },

  async "Sign-up: an invite link opens Start a class with the code filled in"() {
    const app = start({ signedIn: false, hash: "invite=abc123" });
    await wait(800);
    check("Start a class form shown", app.page().includes("<h1>Start a class</h1>"));
    check("invite code filled in", /id="ainv"[^>]*value="abc123"/.test(app.page()));
    check("nothing downloaded before sign-in", app.fetched.length === 0, JSON.stringify(app.fetched));
  },

  async "Admin: only the app admin sees Invite a teacher"() {
    const admin = start({ server: teacher(), hash: "tset", rpc: { is_app_admin: true } });
    const other = start({ server: teacher(), hash: "tset", rpc: { is_app_admin: false } });
    await wait(1500);
    check("admin sees the card", admin.page().includes('data-act="teacherinvite"'));
    check("other teachers do not", other.page().includes("Class settings") && !other.page().includes('data-act="teacherinvite"'));
  },

  async "Notifications: which teacher actions notify the class"() {
    const app = start({ server: teacher({ week: 1, material: "disciple" }), hash: "tset" });
    await wait(1500);
    app.click("postmsg");                                                  // empty message: clears, no notice
    app.type("msg", "Bring your Bible on Sunday!"); app.click("postmsg");  // real message
    app.click("week", { "data-n": "2" }); app.click("week", { "data-n": "2" });  // next lesson (two taps)
    app.click("checkin");                                                  // open check-in
    await wait(300);
    app.click("week", { "data-n": "1" }); app.click("week", { "data-n": "1" });  // back a lesson: no notice
    await wait(2500);
    check("message, next lesson and check-in each notify once", JSON.stringify(app.invokes.slice().sort()) === '["checkin","lesson","message"]', JSON.stringify(app.invokes));
    check("teacher is told how many phones were notified", /phones were notified/.test(app.toast()));
  },

  async "Live updates: listens to the class, groups changes, ignores own saves"() {
    const app = start({ server: student(), hash: "shome" });
    await wait(1500);
    check("student listens to their class only (no other people's journals)", app.subs.join(" ") ===
      "classes[id=eq.c1] profiles[class_id=eq.c1] prayers[class_id=eq.c1] attendance[class_id=eq.c1] manual_students[class_id=eq.c1] student_notes[class_id=eq.c1] prayed", app.subs.join(" "));
    let base = app.counts.classes || 0;
    app.emit("prayers", { new: { id: "x", user_id: "someone-else", class_id: "c1" } });
    app.emit("classes", { new: { id: "c1", message: "hi" } });
    await wait(2000);
    check("two changes by others cause one refresh", (app.counts.classes || 0) - base === 1, String((app.counts.classes || 0) - base));
    base = app.counts.classes || 0;
    app.emit("prayed", { new: { user_id: UID, prayer_id: "x" } });
    app.emit("profiles", { new: { id: UID, role: "student", class_id: "c1" } });
    app.emit("prayers", { new: {}, old: {}, errors: ["Error 401: Unauthorized"] });
    await wait(2000);
    check("own saves and 'Unauthorized' notices cause no refresh", (app.counts.classes || 0) - base === 0, String((app.counts.classes || 0) - base));
  }
};

(async () => {
  for (const [name, fn] of Object.entries(tests)) {
    results.push(name);
    try { await fn(); } catch (e) { check("ran without crashing", false, e && e.stack ? e.stack.split("\n").slice(0, 2).join(" ") : String(e)); }
  }
  console.log(results.join("\n"));
  console.log(failed ? "\n" + failed + " check(s) FAILED" : "\nAll checks passed.");
  process.exit(failed ? 1 : 0);
})();
