// Sends push notifications to a class's students.
// Called by the app (signed in) with { kind }: "message" | "lesson" | "checkin" (teachers), or "test" (anyone, to their own phones).
// The text always comes from the database, never from the caller, so nobody can send made-up messages through it.
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

type Sub = { endpoint: string; p256dh: string; auth: string };
type Note = { title: string; body: string; url: string; tag: string };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const { data: who, error: whoErr } = await db.auth.getUser(token);
  if (whoErr || !who?.user) return json({ error: "not signed in" }, 401);
  const uid = who.user.id;

  let kind = "";
  try { kind = String((await req.json())?.kind || ""); } catch { /* no body */ }
  if (!["message", "lesson", "checkin", "test"].includes(kind)) return json({ error: "unknown kind" }, 400);

  const { data: keys } = await db.from("app_secrets").select("name,value");
  const k = Object.fromEntries((keys || []).map((r: { name: string; value: string }) => [r.name, r.value]));
  if (!k.vapid_public || !k.vapid_private) return json({ error: "push is not set up" }, 500);
  webpush.setVapidDetails(k.vapid_subject || "https://example.com", k.vapid_public, k.vapid_private);

  let note: Note, userIds: string[], classId: string | null = null;

  if (kind === "test") {
    note = { title: "Notifications are on", body: "You will hear from your class here.", url: "#shome", tag: "test" };
    userIds = [uid];
  } else {
    const { data: me } = await db.from("profiles").select("role,class_id").eq("id", uid).maybeSingle();
    if (!me || me.role !== "teacher" || !me.class_id) return json({ error: "only a class leader can do this" }, 403);
    classId = me.class_id;
    const { data: c } = await db.from("classes")
      .select("name,week,message,checkin_open,checkin_at").eq("id", classId).maybeSingle();
    if (!c) return json({ error: "class not found" }, 404);
    const cname = c.name || "Your class";

    if (kind === "message") {
      const m = (c.message || "").trim();
      if (!m) return json({ error: "no message posted" }, 400);
      note = { title: "Message from " + cname, body: m.length > 160 ? m.slice(0, 157) + "…" : m, url: "#shome", tag: "message" };
    } else if (kind === "lesson") {
      note = { title: "Lesson " + c.week + " is open", body: cname + ": this week's lesson is ready. Tap to read it.", url: "#sl" + c.week, tag: "lesson" };
    } else {
      const fresh = c.checkin_at && Date.now() - Date.parse(c.checkin_at) < 4 * 3600 * 1000;
      if (!c.checkin_open || !fresh) return json({ error: "check-in is not open" }, 400);
      note = { title: "Check-in is open", body: cname + ": tap “I'm here today” in the app.", url: "#shome", tag: "checkin" };
    }

    // the same kind of notice goes out at most once a minute per class
    const since = new Date(Date.now() - 60 * 1000).toISOString();
    const { data: recent } = await db.from("push_log").select("id").eq("class_id", classId).eq("kind", kind).gte("sent_at", since).limit(1);
    if (recent && recent.length) return json({ skipped: "sent less than a minute ago" });

    const { data: studs } = await db.from("profiles").select("id").eq("class_id", classId).eq("role", "student");
    userIds = (studs || []).map((s: { id: string }) => s.id);
  }

  let subs: Sub[] = [];
  if (userIds.length) {
    const { data } = await db.from("push_subs").select("endpoint,p256dh,auth").in("user_id", userIds);
    subs = data || [];
  }

  const payload = JSON.stringify(note);
  const results = await Promise.allSettled(subs.map((s) =>
    webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 86400 })
  ));
  const gone: string[] = [];
  let sent = 0, failed = 0;
  results.forEach((r, i) => {
    if (r.status === "fulfilled") sent++;
    else {
      failed++;
      const code = (r.reason as { statusCode?: number })?.statusCode;
      if (code === 404 || code === 410) gone.push(subs[i].endpoint); // that phone turned notifications off or was reset
    }
  });
  if (gone.length) await db.from("push_subs").delete().in("endpoint", gone);
  if (classId) await db.from("push_log").insert({ class_id: classId, kind, sent_by: uid, recipients: sent });

  return json({ sent, failed, removed: gone.length });
});
