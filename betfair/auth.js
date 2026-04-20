// betfair/auth.js
// Non-interactive (cert-based) login for Betfair API-NG.
// Produces a short-lived session token cached in memory.
//
// Required environment variables (redacted — set these in Vercel → Project → Settings → Env):
//   BETFAIR_USERNAME       Betfair Australia account username
//   BETFAIR_PASSWORD       account password
//   BETFAIR_APP_KEY        the DELAYED App Key from developer.betfair.com
//   BETFAIR_CERT_PEM       PEM-encoded client certificate (the .crt content, newlines preserved)
//   BETFAIR_KEY_PEM        PEM-encoded private key (the .key content, newlines preserved)
//
// Optional:
//   BETFAIR_IDENTITY_URL   override auth endpoint (default: AU)
//
// Session tokens expire after ~4 hours of idle OR ~8 hours total.
// We cache for 3.5 hours and refresh aggressively on 401s.

const https = require('https');
const axios = require('axios');

const DEFAULT_IDENTITY_URL = 'https://identitysso-cert.betfair.com.au/api/certlogin';
const SESSION_TTL_MS = 3.5 * 60 * 60 * 1000; // 3h 30m

let sessionCache = {
  token: null,
  issuedAt: 0,
};

function redact(token) {
  if (!token || token.length < 10) return '***';
  return token.slice(0, 4) + '...' + token.slice(-4);
}

function buildHttpsAgent() {
  const cert = process.env.BETFAIR_CERT_PEM;
  const key = process.env.BETFAIR_KEY_PEM;
  if (!cert || !key) {
    throw new Error('BETFAIR_CERT_PEM and BETFAIR_KEY_PEM must be set');
  }
  // Vercel env vars sometimes escape newlines — normalise both cases.
  const normalisedCert = cert.replace(/\\n/g, '\n');
  const normalisedKey = key.replace(/\\n/g, '\n');
  return new https.Agent({
    cert: normalisedCert,
    key: normalisedKey,
    keepAlive: true,
  });
}

async function login(logger = console) {
  const username = process.env.BETFAIR_USERNAME;
  const password = process.env.BETFAIR_PASSWORD;
  const appKey = process.env.BETFAIR_APP_KEY;
  const url = process.env.BETFAIR_IDENTITY_URL || DEFAULT_IDENTITY_URL;

  if (!username || !password || !appKey) {
    throw new Error('BETFAIR_USERNAME, BETFAIR_PASSWORD, BETFAIR_APP_KEY must be set');
  }

  const agent = buildHttpsAgent();
  const body = `username=${encodeURIComponent(username)}&password=${encodeURIComponent(password)}`;

  try {
    const { data } = await axios.post(url, body, {
      httpsAgent: agent,
      headers: {
        'X-Application': appKey,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      timeout: 15000,
    });

    if (data.loginStatus !== 'SUCCESS' || !data.sessionToken) {
      throw new Error(`Betfair login failed: ${data.loginStatus || 'no token returned'}`);
    }

    sessionCache = {
      token: data.sessionToken,
      issuedAt: Date.now(),
    };
    logger.log && logger.log(`Betfair login OK (session ${redact(data.sessionToken)})`);
    return data.sessionToken;
  } catch (err) {
    const status = err.response && err.response.status;
    const payload = err.response && err.response.data;
    const detail = payload ? JSON.stringify(payload) : err.message;
    throw new Error(`Betfair login error${status ? ` (HTTP ${status})` : ''}: ${detail}`);
  }
}

// Returns a valid session token, refreshing if expired or missing.
async function getSessionToken(logger = console) {
  const age = Date.now() - sessionCache.issuedAt;
  if (sessionCache.token && age < SESSION_TTL_MS) {
    return sessionCache.token;
  }
  return await login(logger);
}

// Forces a re-login (e.g. after a 401 INVALID_SESSION_INFORMATION).
async function invalidateSession(logger = console) {
  sessionCache = { token: null, issuedAt: 0 };
  return await login(logger);
}

// Diagnostics
function getSessionInfo() {
  return {
    hasToken: !!sessionCache.token,
    tokenPreview: sessionCache.token ? redact(sessionCache.token) : null,
    ageSeconds: sessionCache.token ? Math.round((Date.now() - sessionCache.issuedAt) / 1000) : null,
    ttlSeconds: Math.round(SESSION_TTL_MS / 1000),
  };
}

module.exports = {
  getSessionToken,
  invalidateSession,
  getSessionInfo,
};
