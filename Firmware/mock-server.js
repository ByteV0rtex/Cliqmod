// ============================================================
//  CLIQMOD MOCK SERVER
//  Mirrors the real firmware's endpoints/JSON shapes exactly, so the app
//  can be built and tested with zero hardware. No dependencies — just:
//
//    node mock-server.js
//
//  Then point the app at http://localhost:8080 instead of the brain's IP.
//  Swap in the real device later by changing one base URL.
// ============================================================

const http = require('http');

const PORT = 8080;

// ── Fake state ────────────────────────────────────────────────
// Starts in AP/setup mode so you can build and test the FIRST-RUN pairing
// screen too, not just Deck/Config mode. POST /api/wifi/join flips this to
// "sta" after a simulated delay.
let network = {
  mode: 'ap',
  connected: false,
  ssid: 'Cliqmod',
  ip: '192.168.4.1',
  hostname: 'cliqmod.local',
  lastError: ''
};

let activeProfile = 0;
let profiles = [
  {
    name: 'Default',
    mappings: [
      { id: 0, label: 'Undo', source: 'Brain Enc Click', srcCode: 0xF0, controlId: 0, eventType: 0, eventTypeLabel: 'none', keycombo: 'CTRL+Z', isString: false },
      { id: 1, label: 'Redo', source: 'Brain Btn Left',  srcCode: 0xF1, controlId: 0, eventType: 0, eventTypeLabel: 'none', keycombo: 'CTRL+Y', isString: false },
      { id: 2, label: 'Save', source: 'Brain Btn Right', srcCode: 0xF2, controlId: 0, eventType: 0, eventTypeLabel: 'none', keycombo: 'CTRL+S', isString: false }
    ]
  },
  { name: 'DAW', mappings: [] },
  { name: 'Video Edit', mappings: [] },
  { name: 'Gaming', mappings: [] },
  { name: 'Custom', mappings: [] }
];

// One fake Knob+Slider on the left, one fake Button Matrix on the right —
// enough to exercise both module types' source lists and Deck mode rendering.
let modules = [
  { present: true,  label: 'K+Slide', side: 'L', pos: 1, address: 0x10, type: 'knob_slider', encValues: [50, 50, 0, 0], faderValues: [80, 20, 0, 0] },
  { present: false, label: '',        side: 'L', pos: 2, address: 0,    type: 'unknown',      encValues: null, faderValues: null },
  { present: false, label: '',        side: 'L', pos: 3, address: 0,    type: 'unknown',      encValues: null, faderValues: null },
  { present: true,  label: 'Buttons', side: 'R', pos: 1, address: 0x20, type: 'buttons',      encValues: null, faderValues: null },
  { present: false, label: '',        side: 'R', pos: 2, address: 0,    type: 'unknown',      encValues: null, faderValues: null },
  { present: false, label: '',        side: 'R', pos: 3, address: 0,    type: 'unknown',      encValues: null, faderValues: null }
];

// ── Diagnostics (uptime, bus health, power budget) ──────────────
const bootTime = Date.now();
let diagnostics = {
  left:  { busRecoveries: 0, lastHeartbeatAgoMs: 0, modulesConnected: 1, powerBudgetMax: 3 },
  right: { busRecoveries: 0, lastHeartbeatAgoMs: 0, modulesConnected: 1, powerBudgetMax: 3 }
};

function buildDiagnostics() {
  return {
    uptimeMs: Date.now() - bootTime,
    left:  diagnostics.left,
    right: diagnostics.right
  };
}

// ── Helpers ──────────────────────────────────────────────────
function buildSources() {
  const sources = [
    { srcCode: 0xF0, controlId: 0, eventType: 0, eventTypeLabel: 'none', label: 'Brain Enc Click' },
    { srcCode: 0xF1, controlId: 0, eventType: 0, eventTypeLabel: 'none', label: 'Brain Btn Left' },
    { srcCode: 0xF2, controlId: 0, eventType: 0, eventTypeLabel: 'none', label: 'Brain Btn Right' }
  ];
  for (const m of modules) {
    if (!m.present) continue;
    const prefix = `${m.side}${m.pos}`;
    if (m.type === 'knob_slider') {
      for (let c = 0; c < 2; c++) {
        sources.push({ srcCode: m.address, controlId: c, eventType: 0x11, eventTypeLabel: 'enc_cw',  label: `${prefix} Enc${c+1} CW` });
        sources.push({ srcCode: m.address, controlId: c, eventType: 0x12, eventTypeLabel: 'enc_ccw', label: `${prefix} Enc${c+1} CCW` });
        sources.push({ srcCode: m.address, controlId: c, eventType: 0x02, eventTypeLabel: 'enc_click', label: `${prefix} Enc${c+1} Click` });
      }
      for (let c = 0; c < 2; c++) {
        sources.push({ srcCode: m.address, controlId: c, eventType: 0x04, eventTypeLabel: 'fader', label: `${prefix} Fader${c+1}` });
      }
    } else if (m.type === 'buttons') {
      for (let c = 0; c < 16; c++) {
        sources.push({ srcCode: m.address, controlId: c, eventType: 0x05, eventTypeLabel: 'button', label: `${prefix} Key${c+1}` });
      }
    }
  }
  return { sources };
}

function buildState() {
  return {
    activeProfile,
    firmware: '0.4.0-mock',
    network,
    profiles,
    modules,
    diagnostics: buildDiagnostics()
  };
}

function sendJson(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type'
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', chunk => data += chunk);
    req.on('end', () => {
      try { resolve(data ? JSON.parse(data) : {}); }
      catch (e) { reject(e); }
    });
  });
}

// ── Server ───────────────────────────────────────────────────
const server = http.createServer(async (req, res) => {
  const url = req.url.split('?')[0];

  if (req.method === 'OPTIONS') { sendJson(res, 200, {}); return; }

  try {
    if (url === '/api/state' && req.method === 'GET') {
      sendJson(res, 200, buildState());

    } else if (url === '/api/sources' && req.method === 'GET') {
      sendJson(res, 200, buildSources());

    } else if (url === '/api/profile' && req.method === 'POST') {
      const body = await readBody(req);
      if (typeof body.index === 'number' && body.index >= 0 && body.index < profiles.length) {
        activeProfile = body.index;
      }
      sendJson(res, 200, { ok: true });

    } else if (url === '/api/mappings' && req.method === 'POST') {
      const body = await readBody(req);
      const idx = typeof body.profile === 'number' ? body.profile : activeProfile;
      if (idx < 0 || idx >= profiles.length) { sendJson(res, 400, { error: 'bad profile' }); return; }
      profiles[idx].mappings = (body.mappings || []).map((m, i) => ({
        id: i,
        label: m.label || '',
        source: m.srcCode >= 0xF0 ? { 0xF0: 'Brain Enc Click', 0xF1: 'Brain Btn Left', 0xF2: 'Brain Btn Right' }[m.srcCode] || 'Unknown'
                                   : `Module 0x${(m.srcCode||0).toString(16).toUpperCase()}`,
        srcCode: m.srcCode || 0,
        controlId: m.controlId || 0,
        eventType: m.eventType || 0,
        eventTypeLabel: m.isString ? 'none' : 'none',
        keycombo: m.keycombo || '',
        isString: !!m.isString
      }));
      sendJson(res, 200, { ok: true });

    } else if (url === '/api/trigger' && req.method === 'POST') {
      const body = await readBody(req);
      if (typeof body.mappingId === 'number') {
        const m = profiles[activeProfile].mappings.find(mm => mm.id === body.mappingId);
        if (!m) { sendJson(res, 404, { ok: false, error: 'mapping not found' }); return; }
        console.log(`[TRIGGER] mapping ${body.mappingId}: ${m.label} (${m.isString ? 'text' : m.keycombo})`);
        sendJson(res, 200, { ok: true });
      } else if (typeof body.keycombo === 'string') {
        console.log(`[TRIGGER] ad-hoc: ${body.isString ? 'type "' + body.keycombo + '"' : body.keycombo}`);
        sendJson(res, 200, { ok: true });
      } else {
        sendJson(res, 400, { ok: false, error: 'mappingId or keycombo required' });
      }

    } else if (url === '/api/rescan' && req.method === 'POST') {
      // Real firmware re-enumerates I2C here; mock just acknowledges.
      sendJson(res, 200, { ok: true });

    } else if (url === '/api/wifi/join' && req.method === 'POST') {
      const body = await readBody(req);
      if (!body.ssid) { sendJson(res, 200, { ok: false, error: 'SSID required' }); return; }

      // Test hook: a password containing "fail" simulates a bad join, so you can
      // build/test the error-state UI without needing real hardware to fail on.
      await new Promise(r => setTimeout(r, 1500)); // simulate real join latency
      if ((body.password || '').includes('fail')) {
        network.lastError = 'Could not reach that network — check the password and try again';
        sendJson(res, 200, { ok: false, error: network.lastError });
        return;
      }

      network = { mode: 'sta', connected: true, ssid: body.ssid, ip: '192.168.1.42', hostname: 'cliqmod.local', lastError: '' };
      sendJson(res, 200, { ok: true, ip: network.ip });

    } else if (url === '/api/wifi/forget' && req.method === 'POST') {
      network = { mode: 'ap', connected: false, ssid: 'Cliqmod', ip: '192.168.4.1', hostname: 'cliqmod.local', lastError: '' };
      sendJson(res, 200, { ok: true });

    } else {
      sendJson(res, 404, { error: 'not found' });
    }
  } catch (e) {
    sendJson(res, 400, { error: 'bad request', detail: String(e) });
  }
});

server.listen(PORT, () => {
  console.log(`Cliqmod mock server running at http://localhost:${PORT}`);
  console.log(`Starts in AP/setup mode — POST /api/wifi/join to simulate a successful pairing.`);
  console.log(`Use a password containing "fail" to simulate a failed join.`);
});