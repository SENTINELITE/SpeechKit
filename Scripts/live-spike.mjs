#!/usr/bin/env node
// Phase 0 spike for the GPT-Live speech-to-speech plan (PLAN-SPEECH-TO-SPEECH.md).
//
// Opens a gpt-live-1 WebSocket session, optionally streams a WAV file as microphone
// input, logs every server event, saves assistant audio to a WAV, and writes raw
// event JSON fixtures for unit tests. Needs Node 22+ (built-in WebSocket). No deps.
//
// Usage:
//   OPENAI_API_KEY=... node Scripts/live-spike.mjs [options]
//
// Options:
//   --delegation none|responses|client   session.delegation mode (default: none)
//   --backend <model>                    responses delegation backend model (default: gpt-5.6-luna)
//   --voice <name>                       audio.output.voice (default: marin)
//   --rate 24000|16000                   PCM sample rate (default: 24000)
//   --wav <path>                         16-bit mono PCM WAV at --rate to stream as input
//   --listen <seconds>                   how long to wait for output after input ends (default: 12)
//   --idle <seconds>                     send nothing and see when/if the server closes (default: 0)
//   --out <path>                         where to write assistant audio (default: Scripts/live-output.wav)
//   --fixtures <dir>                     where to write event fixtures (default: Scripts/live-fixtures)
//   --probe-secrets                      try the client_secrets endpoints and report status
//   --probe-commands                     after session.started, exercise append/update/mute/bogus/response.create and record acks
//   --endpoint <wss url>                 override socket URL

import fs from "node:fs";
import path from "node:path";

const args = parseArgs(process.argv.slice(2));
const apiKey = process.env.OPENAI_API_KEY || process.env.SPEECHKIT_OPENAI_LIVE_KEY;
if (!apiKey) {
  console.error("Set OPENAI_API_KEY (or SPEECHKIT_OPENAI_LIVE_KEY) in the environment.");
  process.exit(2);
}

const delegationMode = args.delegation ?? "none";
const backendModel = args.backend ?? "gpt-5.6-luna";
const voice = args.voice ?? "marin";
const rate = Number(args.rate ?? 24000);
const listenSeconds = Number(args.listen ?? 12);
const idleSeconds = Number(args.idle ?? 0);
const outPath = args.out ?? "Scripts/live-output.wav";
const fixtureDir = args.fixtures ?? "Scripts/live-fixtures";
const endpoint = args.endpoint ?? "wss://api.openai.com/v1/live/sessions";

if (args["probe-secrets"]) {
  await probeSecrets();
  process.exit(0);
}

fs.mkdirSync(fixtureDir, { recursive: true });

const session = {
  model: "gpt-live-1",
  instructions:
    "You are a concise voice assistant. Answer in one short sentence. If asked the capital of France, say Paris.",
  audio: {
    format: { type: "audio/pcm", rate },
    output: { voice },
  },
};
if (delegationMode === "responses") {
  session.delegation = {
    type: "responses",
    responses: { model: backendModel, tool_choice: "auto" },
  };
} else if (delegationMode === "client") {
  session.delegation = { type: "client" };
}

console.log(`connecting ${endpoint}`);
console.log("session.start payload:", JSON.stringify(session, null, 2));

const ws = new WebSocket(endpoint, {
  headers: { Authorization: `Bearer ${apiKey}` },
});

const outputChunks = [];
const eventCounts = new Map();
const fixturesSeen = new Set();
let started = false;
let closed = false;
let inputTranscript = "";
let outputTranscript = "";
const t0 = Date.now();

const stamp = () => `[${((Date.now() - t0) / 1000).toFixed(2)}s]`;

ws.addEventListener("open", () => {
  console.log(stamp(), "socket open, sending session.start");
  ws.send(JSON.stringify({ type: "session.start", event_id: "evt_start", session }));
});

ws.addEventListener("error", (event) => {
  console.error(stamp(), "socket error", event.message ?? event);
});

ws.addEventListener("close", (event) => {
  console.log(stamp(), `socket closed code=${event.code} reason=${JSON.stringify(event.reason)}`);
  finish();
});

ws.addEventListener("message", async (event) => {
  const raw = typeof event.data === "string" ? event.data : Buffer.from(await event.data.arrayBuffer()).toString();
  let msg;
  try {
    msg = JSON.parse(raw);
  } catch {
    console.log(stamp(), "non-JSON message", raw.slice(0, 200));
    return;
  }
  const type = msg.type ?? "?";
  eventCounts.set(type, (eventCounts.get(type) ?? 0) + 1);
  saveFixture(type, msg);

  switch (type) {
    case "session.started":
      started = true;
      console.log(stamp(), "session.started id=", msg.session?.id);
      console.log("resolved session:", JSON.stringify(msg.session, null, 2));
      runScenario().catch((err) => console.error("scenario failed", err));
      break;
    case "session.output_audio.delta": {
      const bytes = Buffer.from(msg.delta, "base64");
      outputChunks.push(bytes);
      if (eventCounts.get(type) % 25 === 1) console.log(stamp(), `output_audio.delta (${bytes.length} bytes, ${outputChunks.length} chunks so far)`);
      break;
    }
    case "session.input_transcript.delta":
      inputTranscript += msg.delta;
      console.log(stamp(), `user  [${msg.start_ms}-${msg.end_ms}) ${JSON.stringify(msg.delta)}`);
      break;
    case "session.output_transcript.delta":
      outputTranscript += msg.delta;
      console.log(stamp(), `model [${msg.start_ms}-${msg.end_ms}) ${JSON.stringify(msg.delta)}`);
      break;
    case "session.closed":
      closed = true;
      console.log(stamp(), "session.closed", JSON.stringify({ reason: msg.reason, usage: msg.usage }));
      break;
    case "error":
      console.log(stamp(), "ERROR", JSON.stringify(msg.error ?? msg));
      break;
    default:
      console.log(stamp(), type, summarize(msg));
  }
});

async function runScenario() {
  if (args["probe-commands"]) {
    await probeCommands();
    return;
  }
  if (idleSeconds > 0) {
    console.log(stamp(), `idle probe: sending nothing for ${idleSeconds}s`);
    await sleep(idleSeconds * 1000);
    if (!closed) await closeGracefully();
    return;
  }

  if (args.wav) {
    const pcm = readWavPCM(args.wav, rate);
    const bytesPerChunk = (rate * 2) / 10; // 100 ms
    console.log(stamp(), `streaming ${args.wav} (${pcm.length} bytes, ${(pcm.length / (rate * 2)).toFixed(2)}s) in ${bytesPerChunk}-byte chunks`);
    for (let offset = 0; offset < pcm.length; offset += bytesPerChunk) {
      const chunk = pcm.subarray(offset, Math.min(offset + bytesPerChunk, pcm.length));
      ws.send(JSON.stringify({ type: "session.input_audio.append", audio: chunk.toString("base64") }));
      await sleep(100);
    }
    // Trailing silence so the server can detect end of speech.
    const silence = Buffer.alloc(bytesPerChunk);
    for (let i = 0; i < 15; i++) {
      ws.send(JSON.stringify({ type: "session.input_audio.append", audio: silence.toString("base64") }));
      await sleep(100);
    }
  } else {
    console.log(stamp(), "no --wav given; sending 1s of silence, then waiting");
    const silence = Buffer.alloc((rate * 2) / 10);
    for (let i = 0; i < 10; i++) {
      ws.send(JSON.stringify({ type: "session.input_audio.append", audio: silence.toString("base64") }));
      await sleep(100);
    }
  }

  console.log(stamp(), `listening for ${listenSeconds}s`);
  await sleep(listenSeconds * 1000);
  await closeGracefully();
}

async function probeCommands() {
  const send = (obj) => { console.log(stamp(), "-> " + JSON.stringify(obj).slice(0, 200)); ws.send(JSON.stringify(obj)); };
  send({ type: "session.instructions.append", event_id: "ctx_instructions_1", delegation_id: null, content: "The user prefers short answers." });
  await sleep(1500);
  send({ type: "session.thinking.append", event_id: "ctx_thinking_1", delegation_id: null, content: "The user's account is in good standing." });
  await sleep(1500);
  send({ type: "session.commentary.append", event_id: "ctx_commentary_1", delegation_id: null, content: "Your order shipped this morning." });
  await sleep(1500);
  send({ type: "session.input_audio.mute", event_id: "mute_1" });
  await sleep(1000);
  send({ type: "session.input_audio.unmute", event_id: "unmute_1" });
  await sleep(1000);
  send({ type: "session.update", event_id: "update_1", session: { delegation: { type: "responses", responses: { model: backendModel, instructions: "Be terse.", tool_choice: "auto" } } } });
  await sleep(1500);
  send({ type: "session.bogus", event_id: "bogus_1" });
  await sleep(1000);
  send({ type: "session.instructions.append", event_id: "ctx_bad_1", delegation_id: "not-a-real-delegation", content: "x" });
  await sleep(1000);
  if (delegationMode === "responses") {
    send({ type: "response.item.create", event_id: "item_1", item: { type: "message", role: "user", content: [{ type: "input_text", text: "Say the word pineapple." }] } });
    await sleep(1000);
    send({ type: "response.create", event_id: "resp_1" });
    await sleep(4000);
    send({ type: "response.create", event_id: "resp_2", bogus_param: true });
    await sleep(1000);
    send({ type: "response.item.create", event_id: "item_2", bogus_param: true });
    await sleep(1000);
    send({ type: "response.create", event_id: "resp_3", instructions: "Be terse." });
    await sleep(3000);
  }
  await closeGracefully();
}

async function closeGracefully() {
  console.log(stamp(), "sending session.close, waiting up to 15s for session.closed");
  ws.send(JSON.stringify({ type: "session.close" }));
  const deadline = Date.now() + 15000;
  while (!closed && Date.now() < deadline) await sleep(100);
  if (!closed) console.log(stamp(), "no session.closed within 15s");
  ws.close();
}

function finish() {
  if (outputChunks.length > 0) {
    const pcm = Buffer.concat(outputChunks);
    fs.writeFileSync(outPath, wavFromPCM(pcm, rate));
    console.log(`wrote ${outPath}: ${(pcm.length / (rate * 2)).toFixed(2)}s of assistant audio`);
  }
  console.log("\n=== summary ===");
  console.log("session.started received:", started);
  console.log("session.closed received:", closed);
  console.log("user transcript:", JSON.stringify(inputTranscript));
  console.log("model transcript:", JSON.stringify(outputTranscript));
  console.log("event counts:");
  for (const [type, count] of [...eventCounts.entries()].sort()) console.log(`  ${type}: ${count}`);
  console.log(`fixtures in ${fixtureDir}:`, [...fixturesSeen].sort().join(", "));
  process.exit(0);
}

function saveFixture(type, msg) {
  if (fixturesSeen.has(type)) return;
  fixturesSeen.add(type);
  const copy = structuredClone(msg);
  if (typeof copy.delta === "string" && type.endsWith("audio.delta")) copy.delta = copy.delta.slice(0, 64);
  fs.writeFileSync(path.join(fixtureDir, `${type}.json`), JSON.stringify(copy, null, 2));
}

function summarize(msg) {
  const s = JSON.stringify(msg);
  return s.length > 400 ? s.slice(0, 400) + "…" : s;
}

async function probeSecrets() {
  const attempts = [
    { url: "https://api.openai.com/v1/live/client_secrets", body: { session: { model: "gpt-live-1" } } },
    { url: "https://api.openai.com/v1/realtime/client_secrets", body: { session: { type: "realtime", model: "gpt-realtime" } } },
  ];
  for (const { url, body } of attempts) {
    const res = await fetch(url, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    const text = await res.text();
    console.log(`${url} -> ${res.status}`);
    console.log(redactSecrets(text).slice(0, 600));
    if (res.ok && url.includes("realtime")) {
      try {
        const json = JSON.parse(text);
        const secret = json.value ?? json.client_secret?.value;
        if (secret) await tryLiveWithSecret(secret);
      } catch {}
    }
  }
}

async function tryLiveWithSecret(secret) {
  console.log("trying gpt-live-1 socket with a realtime client secret…");
  await new Promise((resolve) => {
    const socket = new WebSocket(endpoint, { headers: { Authorization: `Bearer ${secret}` } });
    const done = (why) => { console.log("  result:", why); try { socket.close(); } catch {} resolve(); };
    socket.addEventListener("open", () => socket.send(JSON.stringify({ type: "session.start", session: { model: "gpt-live-1" } })));
    socket.addEventListener("message", (e) => done(`message ${String(e.data).slice(0, 300)}`));
    socket.addEventListener("error", (e) => done(`error ${e.message ?? ""}`));
    socket.addEventListener("close", (e) => done(`close ${e.code} ${e.reason}`));
    setTimeout(() => done("timeout"), 8000);
  });
}

function redactSecrets(text) {
  return text.replace(/"value"\s*:\s*"[^"]+"/g, '"value":"<redacted>"');
}

function readWavPCM(file, expectedRate) {
  const buf = fs.readFileSync(file);
  if (buf.toString("ascii", 0, 4) !== "RIFF" || buf.toString("ascii", 8, 12) !== "WAVE") throw new Error("not a WAV file");
  let offset = 12;
  let fmt = null;
  let data = null;
  while (offset + 8 <= buf.length) {
    const id = buf.toString("ascii", offset, offset + 4);
    const size = buf.readUInt32LE(offset + 4);
    const body = buf.subarray(offset + 8, offset + 8 + size);
    if (id === "fmt ") {
      fmt = { format: body.readUInt16LE(0), channels: body.readUInt16LE(2), rate: body.readUInt32LE(4), bits: body.readUInt16LE(14) };
    } else if (id === "data") {
      data = body;
    }
    offset += 8 + size + (size % 2);
  }
  if (!fmt || !data) throw new Error("WAV missing fmt or data chunk");
  if (fmt.format !== 1 || fmt.channels !== 1 || fmt.bits !== 16 || fmt.rate !== expectedRate) {
    throw new Error(`WAV must be PCM16 mono at ${expectedRate} Hz; got ${JSON.stringify(fmt)}. Convert with: afconvert -f WAVE -d LEI16@${expectedRate} -c 1 in.aiff out.wav`);
  }
  return data.length % 2 === 0 ? data : data.subarray(0, data.length - 1);
}

function wavFromPCM(pcm, sampleRate) {
  const header = Buffer.alloc(44);
  header.write("RIFF", 0);
  header.writeUInt32LE(36 + pcm.length, 4);
  header.write("WAVE", 8);
  header.write("fmt ", 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(1, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(sampleRate * 2, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write("data", 36);
  header.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([header, pcm]);
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) continue;
    const key = a.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith("--")) out[key] = true;
    else { out[key] = next; i++; }
  }
  return out;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}
