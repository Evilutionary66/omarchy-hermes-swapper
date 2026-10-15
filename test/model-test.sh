#!/bin/bash
# Model.js is Qt-free on purpose, so the profile/detection logic can be checked
# here without a running shell. Fixtures are real `hermes config get model
# --json` output, captured from this machine.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

node - "$ROOT/Model.js" <<'JS'
const assert = require('assert'), fs = require('fs'), vm = require('vm'), c = {module: {exports: {}}};
vm.runInNewContext(fs.readFileSync(process.argv[2], 'utf8'), c);
const m = c.module.exports;

const LM = {
  context_length: 65536,
  max_tokens: 16384,
  default: "google/gemma-4-12b-qat",
  provider: "custom",
  base_url: "http://127.0.0.1:1234/v1",
  api_mode: "chat_completions",
};
const STRATA = { ...LM, default: "qwen3.8-flash-next-iq3_xxs", base_url: "http://127.0.0.1:8080/v1" };

let failed = 0;
function test(name, f) { try { f(); console.log('ok - ' + name) } catch (e) { failed++; console.error('not ok - ' + name + ': ' + e.message) } }

test("exports the helpers BarWidget.qml relies on", () => {
  for (const k of ["profiles", "profileById", "parseModelJson", "detectProfile", "nextProfile", "setArgs", "statusLine"])
    assert.strictEqual(typeof m[k], "function", `missing ${k}`);
});

test("profiles are complete and internally distinct", () => {
  const ps = m.profiles();
  assert.ok(ps.length >= 2, "need at least two profiles to swap between");
  const ids = new Set(), models = new Set(), urls = new Set();
  for (const p of ps) {
    for (const k of ["id", "label", "shortLabel", "modelId", "baseUrl", "glyph"])
      assert.ok(typeof p[k] === "string" && p[k] !== "", `${p.id || "?"} missing ${k}`);
    assert.ok(!ids.has(p.id), `duplicate id ${p.id}`);
    assert.ok(!models.has(p.modelId), `duplicate modelId ${p.modelId}`);
    assert.ok(!urls.has(p.baseUrl), `duplicate baseUrl ${p.baseUrl}`);
    ids.add(p.id); models.add(p.modelId); urls.add(p.baseUrl);
  }
});

test("profileById resolves known ids and returns null for unknown ones", () => {
  assert.strictEqual(m.profileById("lm-studio").modelId, LM.default);
  assert.strictEqual(m.profileById("strata").baseUrl, STRATA.base_url);
  assert.strictEqual(m.profileById("nope"), null);
  assert.strictEqual(m.profileById(""), null);
  assert.strictEqual(m.profileById(null), null);
});

test("parseModelJson accepts real CLI output and rejects everything else", () => {
  // deepEqual, not deepStrictEqual: Model.js runs in its own VM context, so its
  // objects carry a different prototype than this realm's.
  assert.deepEqual(m.parseModelJson(JSON.stringify(LM)), LM);
  assert.deepEqual(m.parseModelJson("  " + JSON.stringify(STRATA) + "\n"), STRATA);
  assert.strictEqual(m.parseModelJson(""), null);
  assert.strictEqual(m.parseModelJson("   "), null);
  assert.strictEqual(m.parseModelJson(null), null);
  assert.strictEqual(m.parseModelJson(undefined), null);
  assert.strictEqual(m.parseModelJson("not json at all"), null);
  assert.strictEqual(m.parseModelJson('{"default": "x"'), null); // truncated read
  assert.strictEqual(m.parseModelJson("[1,2]"), null);           // wrong shape
  assert.strictEqual(m.parseModelJson('"a string"'), null);
});

test("detectProfile matches on model id first, then base_url", () => {
  assert.strictEqual(m.detectProfile(m.parseModelJson(JSON.stringify(LM))).id, "lm-studio");
  assert.strictEqual(m.detectProfile(m.parseModelJson(JSON.stringify(STRATA))).id, "strata");
  // Model id edited by hand: the base_url still identifies the server.
  assert.strictEqual(m.detectProfile({ default: "someone-elses-model", base_url: STRATA.base_url }).id, "strata");
  // Unknown model on an unknown server.
  assert.strictEqual(m.detectProfile({ default: "someone-elses-model", base_url: "http://127.0.0.1:9999/v1" }), null);
  assert.strictEqual(m.detectProfile({ default: "", base_url: LM.base_url }), null);
  assert.strictEqual(m.detectProfile(null), null);
  assert.strictEqual(m.detectProfile({}), null);
});

test("nextProfile cycles through every profile and back to the start", () => {
  const order = m.profiles().map(p => p.id);
  let current = order[0];
  for (let i = 0; i < order.length; i++) {
    const next = m.nextProfile(current);
    assert.strictEqual(next.id, order[(i + 1) % order.length]);
    current = next.id;
  }
  assert.strictEqual(current, order[0], "cycling must return to the starting profile");
  // An unknown current profile (a manual edit, or a first run with no reading)
  // still produces a valid target.
  assert.ok(m.profiles().some(p => p.id === m.nextProfile("nope").id));
  assert.ok(m.profiles().some(p => p.id === m.nextProfile(null).id));
});

test("setArgs writes only the two keys, one hermes call each", () => {
  const args = m.setArgs(m.profileById("strata"));
  assert.deepEqual(args, [
    ["config", "set", "model.default", "qwen3.8-flash-next-iq3_xxs"],
    ["config", "set", "model.base_url", "http://127.0.0.1:8080/v1"],
  ]);
  for (const argv of args) {
    assert.strictEqual(argv.length, 4, "hermes config set takes exactly one key/value pair");
    assert.ok(["model.default", "model.base_url"].includes(argv[2]), `unexpected key ${argv[2]}`);
    assert.ok(typeof argv[3] === "string" && argv[3] !== "", "empty value would blank the config");
  }
  assert.deepEqual(m.setArgs(null), []);
});

test("statusLine describes the actual state, not just the intent", () => {
  const lm = m.profileById("lm-studio");
  assert.strictEqual(m.statusLine(lm, LM), "LM Studio: google/gemma-4-12b-qat");
  // Config half-written: the widget should say so rather than claim success.
  assert.strictEqual(m.statusLine(m.profileById("strata"), LM), "Strata: Hermes is on google/gemma-4-12b-qat");
  assert.strictEqual(m.statusLine(lm, null), "LM Studio: google/gemma-4-12b-qat");
  assert.strictEqual(m.statusLine(null, LM), "Hermes is using a model this plugin does not know");
  assert.strictEqual(m.statusLine(null, null), "Hermes is using a model this plugin does not know");
});

test("glyphs are single code points encodable as QML string literals", () => {
  for (const p of m.profiles()) {
    const cps = Array.from(p.glyph);
    assert.strictEqual(cps.length, 1, `${p.id} glyph is not one code point`);
    const cp = cps[0].codePointAt(0);
    assert.ok(cp > 0xf000 || cp > 0xe000, `${p.id} glyph U+${cp.toString(16).toUpperCase()} is outside the Nerd Font private use areas`);
    if (cp > 0xffff) {
      const hi = 0xd800 + ((cp - 0x10000) >> 10), lo = 0xdc00 + ((cp - 0x10000) & 0x3ff);
      assert.strictEqual(String.fromCharCode(hi, lo), cps[0], `${p.id} surrogate pair is wrong`);
    }
  }
});

process.exit(failed ? 1 : 0);
JS
