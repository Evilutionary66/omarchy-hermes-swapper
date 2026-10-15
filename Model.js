// Hermes Model Swapper profile table and pure helpers.
//
// Kept Qt-free on purpose, following the shell's KeyboardLayoutModel.js /
// TrayModel.js convention: plain function declarations, no QML imports, so the
// matching logic can be unit tested under node (see test/model-test.sh).

// The two local model servers on this machine. `modelId` and `baseUrl` are the
// exact values written to ~/.hermes/config.yaml via `hermes config set`.
const PROFILES = [
  {
    id: "lm-studio",
    label: "LM Studio",
    shortLabel: "LM",
    modelId: "google/gemma-4-12b-qat",
    baseUrl: "http://127.0.0.1:1234/v1",
    glyph: "\uEC20", // cod-robot
  },
  {
    id: "strata",
    label: "Strata",
    shortLabel: "ST",
    modelId: "qwen3.8-flash-next-iq3_xxs",
    baseUrl: "http://127.0.0.1:8080/v1",
    glyph: "\uF4BC", // oct-cpu
  },
];

// Hermes keys the widget is allowed to write.
const WRITE_KEYS = ["model.default", "model.base_url"];

function profiles() {
  return PROFILES;
}

function profileById(id) {
  const wanted = String(id || "");
  for (const profile of PROFILES) {
    if (profile.id === wanted) return profile;
  }
  return null;
}

// `hermes config get model --json` prints the model block as one JSON object.
// Anything else (empty output, a CLI error, a truncated read) yields null so
// callers can distinguish "unknown" from "a real reading".
function parseModelJson(text) {
  const raw = String(text || "").trim();
  if (raw === "") return null;
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
    return parsed;
  } catch (error) {
    return null;
  }
}

// Identify which profile a config reading belongs to. The model id is the
// strongest signal; base_url is the fallback for configs whose model id was
// edited by hand.
function detectProfile(modelJson) {
  if (!modelJson) return null;
  const modelId = String(modelJson.default || "").trim();
  const baseUrl = String(modelJson.base_url || "").trim();
  if (modelId === "") return null;

  for (const profile of PROFILES) {
    if (profile.modelId === modelId) return profile;
  }
  for (const profile of PROFILES) {
    if (profile.baseUrl === baseUrl) return profile;
  }
  return null;
}

// Next profile to cycle to. An unknown current profile cycles to the first one.
function nextProfile(currentId) {
  const index = PROFILES.findIndex((profile) => profile.id === String(currentId || ""));
  return PROFILES[(index + 1) % PROFILES.length];
}

// argv vectors for `hermes config set`, one key per call: `hermes config get`
// only accepts a single key and `set` takes exactly one key/value pair.
function setArgs(profile) {
  if (!profile) return [];
  return [
    ["config", "set", WRITE_KEYS[0], profile.modelId],
    ["config", "set", WRITE_KEYS[1], profile.baseUrl],
  ];
}

// Human-readable status line for the notification and tooltip.
function statusLine(profile, modelJson) {
  if (!profile) return "Hermes is using a model this plugin does not know";
  const actual = modelJson ? String(modelJson.default || "") : "";
  if (actual !== "" && actual !== profile.modelId) {
    return `${profile.label}: Hermes is on ${actual}`;
  }
  return `${profile.label}: ${profile.modelId}`;
}

// Node-only export guard, mirroring KeyboardLayoutModel.js. QML picks these up
// through the namespace import instead.
if (typeof module !== "undefined") {
  module.exports = {
    PROFILES,
    WRITE_KEYS,
    profiles,
    profileById,
    parseModelJson,
    detectProfile,
    nextProfile,
    setArgs,
    statusLine,
  };
}
