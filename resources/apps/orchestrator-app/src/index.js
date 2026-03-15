const express = require('express');
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');
const crypto = require('crypto');

const app = express();
app.use(express.urlencoded({ extended: true }));
app.use(express.json());

const port = process.env.PORT || 3003;
const configFile = process.env.ORCH_CONFIG_FILE || path.join(__dirname, '..', 'config', 'orchestrator.yaml');

function loadConfig(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  return yaml.load(raw) || {};
}

const cfg = loadConfig(configFile);
const sessions = new Map();

function getCookieValue(req, key) {
  const cookieHeader = req.headers.cookie || '';
  const parts = cookieHeader.split(';').map((p) => p.trim());
  const kv = parts.find((p) => p.startsWith(`${key}=`));
  return kv ? kv.split('=')[1] : null;
}

function getOrCreateSession(req, res) {
  let sid = getCookieValue(req, 'sid');
  if (!sid || !sessions.has(sid)) {
    sid = crypto.randomUUID();
    sessions.set(sid, {
      username: null,
      accessToken: null,
      refreshToken: null,
      exchangedToken: null,
      lastError: null,
      notesPayload: null,
      todoPayload: null
    });
    res.setHeader('Set-Cookie', `sid=${sid}; HttpOnly; Path=/; SameSite=Lax`);
  }

  return sessions.get(sid);
}

function maskToken(token) {
  if (!token) {
    return 'N/A';
  }

  if (token.length < 20) {
    return token;
  }

  return `${token.slice(0, 12)}...${token.slice(-12)}`;
}

function decodeJwtPayload(token) {
  if (!token) {
    return null;
  }

  const parts = token.split('.');
  if (parts.length < 2) {
    return null;
  }

  const payload = parts[1];
  const padded = payload + '='.repeat((4 - (payload.length % 4 || 4)) % 4);
  const base64 = padded.replace(/-/g, '+').replace(/_/g, '/');

  try {
    const json = Buffer.from(base64, 'base64').toString('utf8');
    return JSON.parse(json);
  } catch {
    return null;
  }
}

function tokenEndpointUrl() {
  const base = String(cfg.keycloak?.url || '').replace(/\/$/, '');
  const endpointPath = cfg.keycloak?.tokenEndpoint || `/realms/${cfg.keycloak?.realm || 'master'}/protocol/openid-connect/token`;
  return `${base}${endpointPath}`;
}

function renderPage(session) {
  const tokenPayload = decodeJwtPayload(session.exchangedToken || session.accessToken);
  const username = session.username || tokenPayload?.preferred_username || 'not logged in';

  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${cfg.ui?.title || 'Orchestrator'}</title>
  <style>
    body { font-family: Segoe UI, Tahoma, sans-serif; margin: 24px; background: #f6f8fb; color: #14213d; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 16px; }
    .card { background: #fff; border-radius: 10px; padding: 16px; box-shadow: 0 8px 24px rgba(20,33,61,.08); }
    h1 { margin-top: 0; }
    label { display: block; margin-bottom: 8px; font-weight: 600; }
    input, button, select { width: 100%; padding: 10px; margin-bottom: 10px; }
    button { background: #0d6efd; color: #fff; border: none; border-radius: 6px; cursor: pointer; }
    button:hover { background: #0b5ed7; }
    pre { background: #0e1a2b; color: #d2f0ff; padding: 12px; border-radius: 8px; overflow-x: auto; }
    .error { color: #b00020; font-weight: 600; }
  </style>
</head>
<body>
  <h1>${cfg.ui?.title || 'Orchestrator'}</h1>
  <p>Current user: <strong>${username}</strong></p>
  <div class="grid">
    <section class="card">
      <h2>1. Login Against Keycloak</h2>
      <form method="post" action="/login">
        <label>Username</label>
        <input name="username" required />
        <label>Password</label>
        <input type="password" name="password" required />
        <button type="submit">Login and Collect Token</button>
      </form>
      <p>Access token: ${maskToken(session.accessToken)}</p>
    </section>

    <section class="card">
      <h2>2. Token Exchange For NOTES App</h2>
      <form method="post" action="/exchange">
        <button type="submit">Exchange Token</button>
      </form>
      <p>Exchanged token: ${maskToken(session.exchangedToken)}</p>
    </section>

    <section class="card">
      <h2>3. Get Data From NOTES App</h2>
      <form method="post" action="/notes-data">
        <label>Project ID (optional)</label>
        <input type="number" min="1" name="projectId" />
        <button type="submit">Get Notes Data</button>
      </form>
      <p>This sends Bearer token to NOTES API.</p>
    </section>

    <section class="card">
      <h2>4. Get Data From TODO App</h2>
      <form method="post" action="/todos-data">
        <label>Project ID (optional)</label>
        <input type="number" min="1" name="projectId" />
        <button type="submit">Get TODO Data</button>
      </form>
      <p>This sends Bearer token to TODO API.</p>
    </section>
  </div>

  <section class="card">
    <h2>Latest NOTES Response</h2>
    <pre>${JSON.stringify(session.notesPayload, null, 2)}</pre>
  </section>

  <section class="card">
    <h2>Latest TODO Response</h2>
    <pre>${JSON.stringify(session.todoPayload, null, 2)}</pre>
  </section>

  <section class="card">
    <h2>Status</h2>
    <p class="error">${session.lastError || ''}</p>
  </section>
</body>
</html>`;
}

app.get('/', (req, res) => {
  const session = getOrCreateSession(req, res);
  res.send(renderPage(session));
});

app.post('/login', async (req, res) => {
  const session = getOrCreateSession(req, res);
  session.lastError = null;

  const username = String(req.body.username || '').trim();
  const password = String(req.body.password || '');

  if (!username || !password) {
    session.lastError = 'Username and password are required.';
    return res.redirect('/');
  }

  const body = new URLSearchParams({
    grant_type: 'password',
    client_id: cfg.clients?.orchestrator?.clientId || '',
    client_secret: cfg.clients?.orchestrator?.clientSecret || '',
    username,
    password
  });

  try {
    const response = await fetch(tokenEndpointUrl(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body
    });

    const data = await response.json();

    if (!response.ok) {
      session.lastError = `Login failed: ${data.error || 'unknown error'}`;
      return res.redirect('/');
    }

    session.username = username;
    session.accessToken = data.access_token;
    session.refreshToken = data.refresh_token;
    session.exchangedToken = null;
    return res.redirect('/');
  } catch (err) {
    session.lastError = `Login request error: ${err.message}`;
    return res.redirect('/');
  }
});

app.post('/exchange', async (req, res) => {
  const session = getOrCreateSession(req, res);
  session.lastError = null;

  if (!session.accessToken) {
    session.lastError = 'No access token. Login first.';
    return res.redirect('/');
  }

  const body = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:token-exchange',
    client_id: cfg.clients?.orchestrator?.clientId || '',
    client_secret: cfg.clients?.orchestrator?.clientSecret || '',
    subject_token: session.accessToken,
    subject_token_type: 'urn:ietf:params:oauth:token-type:access_token',
    requested_token_type: 'urn:ietf:params:oauth:token-type:access_token',
    audience: cfg.clients?.notes?.audience || ''
  });

  try {
    const response = await fetch(tokenEndpointUrl(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body
    });

    const data = await response.json();

    if (!response.ok) {
      session.lastError = `Exchange failed: ${data.error || 'unknown error'}`;
      return res.redirect('/');
    }

    session.exchangedToken = data.access_token;
    return res.redirect('/');
  } catch (err) {
    session.lastError = `Exchange request error: ${err.message}`;
    return res.redirect('/');
  }
});

app.post('/notes-data', async (req, res) => {
  const session = getOrCreateSession(req, res);
  session.lastError = null;

  const tokenToUse = session.exchangedToken || session.accessToken;
  if (!tokenToUse) {
    session.lastError = 'No token available. Login first.';
    return res.redirect('/');
  }

  const projectId = String(req.body.projectId || '').trim();
  const qs = projectId ? `?projectId=${encodeURIComponent(projectId)}` : '';
  const url = `${cfg.services?.notesApiBaseUrl || 'http://notes-app:3002'}/notes${qs}`;

  try {
    const response = await fetch(url, {
      headers: {
        Authorization: `Bearer ${tokenToUse}`
      }
    });

    const text = await response.text();
    let payload = text;
    try {
      payload = JSON.parse(text);
    } catch {
      payload = { raw: text };
    }

    session.notesPayload = {
      status: response.status,
      data: payload
    };

    if (!response.ok) {
      session.lastError = `NOTES API error (${response.status})`;
    }

    return res.redirect('/');
  } catch (err) {
    session.lastError = `NOTES request error: ${err.message}`;
    return res.redirect('/');
  }
});

app.post('/todos-data', async (req, res) => {
  const session = getOrCreateSession(req, res);
  session.lastError = null;

  const tokenToUse = session.exchangedToken || session.accessToken;
  if (!tokenToUse) {
    session.lastError = 'No token available. Login first.';
    return res.redirect('/');
  }

  const projectId = String(req.body.projectId || '').trim();
  const qs = projectId ? `?projectId=${encodeURIComponent(projectId)}` : '';
  const url = `${cfg.services?.todoApiBaseUrl || 'http://todo-app:3001'}/todos${qs}`;

  try {
    const response = await fetch(url, {
      headers: {
        Authorization: `Bearer ${tokenToUse}`
      }
    });

    const text = await response.text();
    let payload = text;
    try {
      payload = JSON.parse(text);
    } catch {
      payload = { raw: text };
    }

    session.todoPayload = {
      status: response.status,
      data: payload
    };

    if (!response.ok) {
      session.lastError = `TODO API error (${response.status})`;
    }

    return res.redirect('/');
  } catch (err) {
    session.lastError = `TODO request error: ${err.message}`;
    return res.redirect('/');
  }
});

app.listen(port, () => {
  console.log(`orchestrator-app listening on port ${port}`);
});
