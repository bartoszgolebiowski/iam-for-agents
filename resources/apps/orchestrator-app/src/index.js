const express = require('express');
const crypto = require('crypto');
const path = require('path');

const app = express();
app.use(express.urlencoded({ extended: true }));
app.use(express.json());

// Configure EJS as view engine
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, '..', 'views'));

const port = process.env.PORT || 3003;

// Load configuration from environment variables
const cfg = {
  keycloak: {
    url: process.env.KEYCLOAK_URL || '',
    realm: process.env.KEYCLOAK_REALM || 'master',
  },
  clients: {
    orchestrator: {
      clientId: process.env.ORCHESTRATOR_CLIENT_ID || '',
      clientSecret: process.env.ORCHESTRATOR_CLIENT_SECRET || ''
    },
    notes: {
      audience: process.env.NOTES_AUDIENCE || 'notes-app'
    },
    todo: {
      audience: process.env.TODO_AUDIENCE || 'todo-app'
    }
  },
  services: {
    notesApiBaseUrl: process.env.NOTES_API_URL || 'http://notes-app:3002',
    todoApiBaseUrl: process.env.TODO_API_URL || 'http://todo-app:3001'
  },
  ui: {
    title: process.env.UI_TITLE || 'Orchestrator'
  }
};
const sessions = new Map();

// Validate configuration at startup
function validateConfig() {
  const errors = [];

  if (!cfg.keycloak.url) {
    errors.push('KEYCLOAK_URL environment variable is not set');
  }
  if (!cfg.clients.orchestrator.clientId) {
    errors.push('ORCHESTRATOR_CLIENT_ID environment variable is not set');
  }
  if (!cfg.clients.orchestrator.clientSecret) {
    errors.push('ORCHESTRATOR_CLIENT_SECRET environment variable is not set');
  }

  if (errors.length > 0) {
    console.error('Configuration errors:');
    errors.forEach(err => console.error(`  - ${err}`));
    console.error('\nPlease set the required environment variables.');
  }

  return errors.length === 0;
}

// Log configuration on startup
console.log('=== Orchestrator Configuration ===');
console.log(`Keycloak URL: ${cfg.keycloak.url}`);
console.log(`Keycloak Realm: ${cfg.keycloak.realm}`);
console.log(`Token Endpoint: ${tokenEndpointUrl()}`);
console.log(`Orchestrator Client ID: ${cfg.clients.orchestrator.clientId}`);
console.log(`Notes Audience: ${cfg.clients.notes.audience}`);
console.log(`Notes API URL: ${cfg.services.notesApiBaseUrl}`);
console.log(`TODO API URL: ${cfg.services.todoApiBaseUrl}`);
console.log('==================================\n');

if (!validateConfig()) {
  console.error('Exiting due to configuration errors.');
  process.exit(1);
}

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
      exchangedNotesToken: null,
      exchangedTodoToken: null,
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
  if (cfg.keycloak.tokenEndpoint) {
    return cfg.keycloak.tokenEndpoint;
  }
  const base = String(cfg.keycloak.url || '').replace(/\/$/, '');
  const endpointPath = `/realms/${cfg.keycloak.realm}/protocol/openid-connect/token`;
  return `${base}${endpointPath}`;
}

function renderPage(session) {
  const tokenPayload = decodeJwtPayload(session.exchangedNotesToken || session.exchangedTodoToken || session.accessToken);
  const username = session.username || tokenPayload?.preferred_username || 'not logged in';

  return {
    title: cfg.ui.title,
    username,
    sessions: session,
    maskToken
  };
}

app.get('/', (req, res) => {
  const session = getOrCreateSession(req, res);
  const data = renderPage(session);
  res.render('index', data);
});

app.post('/login', async (req, res) => {
  const session = getOrCreateSession(req, res);
  session.lastError = null;

  // Log incoming request
  console.log('[LOGIN] ========================================');
  console.log('[LOGIN] Incoming request details:');
  console.log(`[LOGIN]   Method: ${req.method}`);
  console.log(`[LOGIN]   URL: ${req.url}`);
  console.log(`[LOGIN]   Content-Type: ${req.get('content-type')}`);
  console.log('[LOGIN] Request body (raw):');
  Object.entries(req.body).forEach(([key, value]) => {
    if (key === 'password') {
      console.log(`[LOGIN]   ${key}: [REDACTED]`);
    } else {
      console.log(`[LOGIN]   ${key}: ${value}`);
    }
  });
  console.log('[LOGIN] ========================================');

  const username = String(req.body.username || '').trim();
  const password = String(req.body.password || '');

  if (!username || !password) {
    session.lastError = 'Username and password are required.';
    console.warn('[LOGIN] Validation failed: Username or password is empty');
    return res.redirect('/');
  }

  const tokenUrl = tokenEndpointUrl();
  console.log(`[LOGIN] Attempting login for user: ${username}`);
  console.log(`[LOGIN] Token endpoint: ${tokenUrl}`);
  console.log(`[LOGIN] Client ID: ${cfg.clients.orchestrator.clientId}`);
  console.log(`[LOGIN] Client Secret: ${maskToken(cfg.clients.orchestrator.clientSecret)}`);

  const body = new URLSearchParams({
    grant_type: 'password',
    client_id: cfg.clients.orchestrator.clientId,
    client_secret: cfg.clients.orchestrator.clientSecret,
    username,
    password,
    scope: 'openid profile email'
  });

  console.log('[LOGIN] Token request parameters (sanitized):');
  console.log(`[LOGIN]   grant_type: password`);
  console.log(`[LOGIN]   client_id: ${cfg.clients.orchestrator.clientId}`);
  console.log(`[LOGIN]   client_secret: ${maskToken(cfg.clients.orchestrator.clientSecret)}`);
  console.log(`[LOGIN]   username: ${username}`);
  console.log(`[LOGIN]   password: [REDACTED]`);
  console.log(`[LOGIN]   scope: openid profile email`);

  try {
    console.log(`[LOGIN] Sending token request to: ${tokenUrl}`);
    const response = await fetch(tokenUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString()
    });

    console.log(`[LOGIN] Response status: ${response.status}`);
    console.log(`[LOGIN] Response status text: ${response.statusText}`);

    const data = await response.json();

    if (!response.ok) {
      const errorMsg = data.error_description || data.error || 'unknown error';
      console.error(`[LOGIN] ✗ Authentication failed`);
      console.error(`[LOGIN]   Error: ${data.error || 'unknown'}`);
      console.error(`[LOGIN]   Description: ${errorMsg}`);
      console.error(`[LOGIN] Full error response:`, JSON.stringify(data, null, 2));
      session.lastError = `Login failed: ${errorMsg}`;
      return res.redirect('/');
    }

    if (!data.access_token) {
      console.error('[LOGIN] ✗ No access_token in response');
      console.error('[LOGIN] Response data:', JSON.stringify(data, null, 2));
      session.lastError = 'Login failed: No access token received from Keycloak';
      return res.redirect('/');
    }

    session.username = username;
    session.accessToken = data.access_token;
    session.refreshToken = data.refresh_token || null;
    session.exchangedToken = null;

    const decoded = decodeJwtPayload(session.accessToken);
    const preferredUsername = decoded?.preferred_username || username;
    console.log(`[LOGIN] ✓ Authentication successful`);
    console.log(`[LOGIN]   User: ${preferredUsername}`);
    console.log(`[LOGIN]   Token expires in: ${data.expires_in}s`);
    console.log(`[LOGIN]   Token type: ${data.token_type}`);
    if (decoded) {
      console.log(`[LOGIN]   JWT Claims:`);
      console.log(`[LOGIN]     - sub: ${decoded.sub}`);
      console.log(`[LOGIN]     - email: ${decoded.email}`);
      console.log(`[LOGIN]     - groups: ${JSON.stringify(decoded.groups || [])}`);
    }

    return res.redirect('/');
  } catch (err) {
    console.error('[LOGIN] ✗ Network/Request error');
    console.error(`[LOGIN]   Error message: ${err.message}`);
    console.error(`[LOGIN]   Error stack:`, err.stack);
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

  const audience = String(req.body.audience || '').trim() || cfg.clients.notes.audience;
  const tokenUrl = tokenEndpointUrl();
  console.log(`[EXCHANGE] Starting token exchange for audience: ${audience}`);

  const body = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:token-exchange',
    client_id: cfg.clients.orchestrator.clientId,
    client_secret: cfg.clients.orchestrator.clientSecret,
    subject_token: session.accessToken,
    subject_token_type: 'urn:ietf:params:oauth:token-type:access_token',
    requested_token_type: 'urn:ietf:params:oauth:token-type:access_token',
    audience: audience
  });

  try {
    console.log(`[EXCHANGE] Token endpoint: ${tokenUrl}`);
    console.log(`[EXCHANGE] Target audience: ${audience}`);

    const response = await fetch(tokenUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString()
    });

    console.log(`[EXCHANGE] Response status: ${response.status}`);

    const data = await response.json();

    if (!response.ok) {
      const errorMsg = data.error_description || data.error || 'unknown error';
      console.error(`[EXCHANGE] Error response: ${errorMsg}`);
      session.lastError = `Exchange failed: ${errorMsg}`;
      return res.redirect('/');
    }

    if (!data.access_token) {
      console.error('[EXCHANGE] No access_token in response');
      session.lastError = 'Exchange failed: No token received from Keycloak';
      return res.redirect('/');
    }

    // Store the exchanged token based on the audience
    if (audience === cfg.clients.notes.audience) {
      session.exchangedNotesToken = data.access_token;
      console.log(`[EXCHANGE] Successfully exchanged token for NOTES app`);
    } else if (audience === cfg.clients.todo.audience) {
      session.exchangedTodoToken = data.access_token;
      console.log(`[EXCHANGE] Successfully exchanged token for TODO app`);
    } else {
      session[`exchanged_${audience}_token`] = data.access_token;
      console.log(`[EXCHANGE] Successfully exchanged token for audience: ${audience}`);
    }

    return res.redirect('/');
  } catch (err) {
    console.error(`[EXCHANGE] Request error: ${err.message}`);
    console.error(err);
    session.lastError = `Exchange request error: ${err.message}`;
    return res.redirect('/');
  }
});

app.post('/notes-data', async (req, res) => {
  const session = getOrCreateSession(req, res);
  session.lastError = null;

  const tokenToUse = session.exchangedNotesToken || session.accessToken;
  if (!tokenToUse) {
    session.lastError = 'No token available. Login first or exchange token for NOTES app.';
    return res.redirect('/');
  }

  const projectId = String(req.body.projectId || '').trim();
  const qs = projectId ? `?projectId=${encodeURIComponent(projectId)}` : '';
  const url = `${cfg.services.notesApiBaseUrl}/notes${qs}`;

  console.log(`[NOTES-DATA] Fetching from: ${url}`);

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
      console.error(`[NOTES-DATA] Error: ${response.status}`);
    } else {
      console.log(`[NOTES-DATA] Success: ${response.status}`);
    }

    return res.redirect('/');
  } catch (err) {
    console.error(`[NOTES-DATA] Request error: ${err.message}`);
    session.lastError = `NOTES request error: ${err.message}`;
    return res.redirect('/');
  }
});

app.post('/todos-data', async (req, res) => {
  const session = getOrCreateSession(req, res);
  session.lastError = null;

  const tokenToUse = session.exchangedTodoToken || session.accessToken;
  if (!tokenToUse) {
    session.lastError = 'No token available. Login first or exchange token for TODO app.';
    return res.redirect('/');
  }

  const projectId = String(req.body.projectId || '').trim();
  const qs = projectId ? `?projectId=${encodeURIComponent(projectId)}` : '';
  const url = `${cfg.services.todoApiBaseUrl}/todos${qs}`;

  console.log(`[TODOS-DATA] Fetching from: ${url}`);

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
      console.error(`[TODOS-DATA] Error: ${response.status}`);
    } else {
      console.log(`[TODOS-DATA] Success: ${response.status}`);
    }

    return res.redirect('/');
  } catch (err) {
    console.error(`[TODOS-DATA] Request error: ${err.message}`);
    session.lastError = `TODO request error: ${err.message}`;
    return res.redirect('/');
  }
});

app.listen(port, () => {
  console.log(`orchestrator-app listening on port ${port}`);
});
