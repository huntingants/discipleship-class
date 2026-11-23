// Checks that a translated lesson file has exactly the same layout as its English file.
//
// Usage:
//   node tools/check-translation.js                         checks every translation the app lists
//   node tools/check-translation.js data/mat-ohb.ceb.json   checks one file against data/mat-ohb.json
//
// A translation may leave lessons out (the app shows those in English), but every lesson it has must
// match the English one: same sections in the same order, same minutes, same block types, same h3
// numbers, same list lengths, the same memory verse, and Bible references kept in English. The
// read / readtog / verse blocks must be identical, and the references in brackets, such as
// "(John 3:16)", must be the same in the same order, because they are the keys for the verse pop-ups.
// Exits with code 1 if anything is wrong.
"use strict";
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const REF_BLOCKS = ["read", "readtog", "verse"];
// a Bible reference with chapter and verse, such as "John 3:16", "1 John 1:9", "Luke 6:46-49", "Gal. 2:20" or "Psalm 5:3; 59:16"
const REF = /(?:\b[1-3] ?|\bI{1,3} )?[A-Z][a-z]+\.? \d+:\s?\d+(?:\s?[-–]\s?\d+)?(?:[;,] ?\d+(?::\d+)?(?:\s?[-–]\s?\d+)?)*/g;

function texts(v, out = []) {
  if (typeof v === "string") out.push(v);
  else if (Array.isArray(v)) v.forEach((x) => texts(x, out));
  else if (v && typeof v === "object") Object.values(v).forEach((x) => texts(x, out));
  return out;
}

// the Bible references written inside brackets anywhere in a block, in order
function bracketRefs(v) {
  const refs = [];
  for (const s of texts(v)) {
    for (const group of s.match(/\([^()]*\)/g) || []) {
      for (const r of group.match(REF) || []) refs.push(r.replace(/\s+/g, " ").replace(/ ?([-–]) ?/g, "$1").trim());
    }
  }
  return refs;
}

function compareLesson(en, tr, say) {
  const where = (s) => `lesson ${en.n}${s}`;
  if (tr.v !== en.v) say(where(""), `memory verse "v" is "${tr.v}", English has "${en.v}"`);
  const enNotes = (en.notes || []).length, trNotes = (tr.notes || []).length;
  if (enNotes !== trNotes) say(where(""), `${trNotes} teacher notes, English has ${enNotes}`);
  for (const k of ["title", "q"]) if (en[k] && !tr[k]) say(where(""), `"${k}" is missing`);
  const es = en.s || [], ts = tr.s || [];
  if (es.length !== ts.length) { say(where(""), `${ts.length} sections, English has ${es.length}`); return; }
  es.forEach((se, i) => {
    const st = ts[i], ws = (k) => where(`, section ${i + 1}` + (k === undefined ? "" : `, block ${k + 1}`));
    if (se.min !== st.min) say(ws(), `${st.min} minutes, English has ${se.min}`);
    if (!st.title) say(ws(), "section title is missing");
    const eb = se.b || [], tb = st.b || [];
    if (eb.length !== tb.length) { say(ws(), `${tb.length} blocks, English has ${eb.length}`); return; }
    eb.forEach((be, k) => {
      const bt = tb[k];
      if (be.t !== bt.t) { say(ws(k), `block type "${bt.t}", English has "${be.t}"`); return; }
      if (be.t === "h3" && be.n !== bt.n) say(ws(k), `h3 number ${bt.n}, English has ${be.n}`);
      if (REF_BLOCKS.includes(be.t) && be.x !== bt.x) say(ws(k), `${be.t} block is "${bt.x}", must stay "${be.x}"`);
      if (Array.isArray(be.x) !== Array.isArray(bt.x)) say(ws(k), "list block is not a list");
      else if (Array.isArray(be.x) && be.x.length !== bt.x.length) say(ws(k), `${be.t} has ${bt.x.length} items, English has ${be.x.length}`);
      if (("i" in be) !== ("i" in bt)) say(ws(k), `"i" (the line above the prayer) is ${"i" in be ? "missing" : "extra"}`);
      if (texts(bt.x).some((s) => !s.trim()) && !texts(be.x).some((s) => !s.trim())) say(ws(k), "has empty text");
      const re = bracketRefs(be), rt = bracketRefs(bt);
      if (re.join("|") !== rt.join("|")) say(ws(k), `Bible references in brackets differ: [${rt.join("; ")}], English has [${re.join("; ")}]`);
    });
  });
}

// compares one translation file with its English file; returns a list of problems (empty when all is well)
function checkFile(trFile, enFile) {
  enFile = enFile || trFile.replace(/\.[a-z]{2,3}\.json$/, ".json");
  const problems = [];
  const say = (where, what) => problems.push(`${where}: ${what}`);
  let en, tr;
  try { en = JSON.parse(fs.readFileSync(enFile, "utf8")); } catch (e) { return [`cannot read ${enFile}: ${e.message}`]; }
  try { tr = JSON.parse(fs.readFileSync(trFile, "utf8")); } catch (e) { return [`cannot read ${trFile}: ${e.message}`]; }
  if (!Array.isArray(tr)) return [`${trFile} is not a list of lessons`];
  const byN = new Map(en.map((l) => [l.n, l]));
  const seen = new Set();
  tr.forEach((l, i) => {
    if (!l || typeof l.n !== "number") { say(`item ${i + 1}`, `has no lesson number "n"`); return; }
    if (seen.has(l.n)) say(`lesson ${l.n}`, "appears twice");
    seen.add(l.n);
    const e = byN.get(l.n);
    if (!e) { say(`lesson ${l.n}`, "is not in the English file"); return; }
    compareLesson(e, l, say);
  });
  return problems;
}

// every translation file the app lists ("langs" in the materials list in index.html)
function listedTranslations() {
  const html = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
  const m = html.match(/<script type="application\/json" id="materials">([\s\S]*?)<\/script>/);
  if (!m) throw new Error("materials list not found in index.html");
  const out = [];
  for (const mat of JSON.parse(m[1])) {
    for (const lang of mat.langs || []) {
      out.push({ tr: path.join(ROOT, "data", `mat-${mat.id}.${lang}.json`), en: path.join(ROOT, "data", `mat-${mat.id}.json`) });
    }
  }
  return out;
}

module.exports = { checkFile, listedTranslations, bracketRefs };

if (require.main === module) {
  const args = process.argv.slice(2);
  const pairs = args.length ? args.map((f) => ({ tr: path.resolve(f) })) : listedTranslations();
  let bad = 0;
  for (const p of pairs) {
    const name = path.relative(ROOT, p.tr);
    const problems = checkFile(p.tr, p.en);
    if (!problems.length) {
      const n = JSON.parse(fs.readFileSync(p.tr, "utf8")).length;
      console.log(`ok    ${name} (${n} lessons match the English layout)`);
    } else {
      bad += problems.length;
      console.log(`FAIL  ${name}`);
      problems.forEach((x) => console.log("      " + x));
    }
  }
  if (!pairs.length) console.log("No translations are listed in index.html.");
  process.exit(bad ? 1 : 0);
}
