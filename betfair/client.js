// betfair/client.js
// Thin JSON-RPC wrapper around the Betfair Betting API.
// Handles session refresh on 401, basic retry, and request-point logging.

const axios = require('axios');
const auth = require('./auth');

const DEFAULT_API_URL = 'https://api-au.betfair.com/exchange/betting/json-rpc/v1';

// rolling tally of requests made in this process — useful for Vercel logs
let requestCount = 0;
let lastResetAt = Date.now();

function getRequestStats() {
  return {
    requestCount,
    uptimeSeconds: Math.round((Date.now() - lastResetAt) / 1000),
  };
}

function resetRequestStats() {
  requestCount = 0;
  lastResetAt = Date.now();
}

async function rpc(method, params, { logger = console, retryOn401 = true } = {}) {
  const url = process.env.BETFAIR_API_URL || DEFAULT_API_URL;
  const appKey = process.env.BETFAIR_APP_KEY;
  if (!appKey) throw new Error('BETFAIR_APP_KEY not set');

  const token = await auth.getSessionToken(logger);

  const body = {
    jsonrpc: '2.0',
    method: `SportsAPING/v1.0/${method}`,
    params: params || {},
    id: Date.now(),
  };

  try {
    requestCount++;
    const { data } = await axios.post(url, body, {
      headers: {
        'X-Application': appKey,
        'X-Authentication': token,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      timeout: 20000,
    });

    // JSON-RPC errors come back as { error: {...} } with HTTP 200
    if (data.error) {
      const errData = data.error.data && data.error.data.APINGException;
      const code = errData && errData.errorCode;
      // Session expired/invalid — try once more after re-login
      if (retryOn401 && (code === 'INVALID_SESSION_INFORMATION' || code === 'NO_SESSION')) {
        logger.log && logger.log(`Betfair session invalid (${code}) — re-logging in`);
        await auth.invalidateSession(logger);
        return await rpc(method, params, { logger, retryOn401: false });
      }
      throw new Error(`Betfair ${method} error: ${code || data.error.message}`);
    }

    return data.result;
  } catch (err) {
    if (err.response && err.response.status === 401 && retryOn401) {
      logger.log && logger.log('Betfair HTTP 401 — re-logging in');
      await auth.invalidateSession(logger);
      return await rpc(method, params, { logger, retryOn401: false });
    }
    // Don't swallow — let caller decide (fetch functions return null on failure)
    throw err;
  }
}

module.exports = {
  rpc,
  getRequestStats,
  resetRequestStats,
};
