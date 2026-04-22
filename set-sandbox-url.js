#!/usr/bin/env node
// Usage: node set-sandbox-url.js <path-to-.p8-file> <key-id> <issuer-id> <app-id>
//
// Get these from App Store Connect > Users and Access > Integrations > App Store Connect API
// App ID is the numeric ID from your app's URL in ASC (e.g. 123456789)

const fs = require('fs');
const crypto = require('crypto');

const [,, p8Path, keyId, issuerId, appId] = process.argv;

if (!p8Path || !keyId || !issuerId || !appId) {
  console.error('Usage: node set-sandbox-url.js <p8-file> <key-id> <issuer-id> <app-id>');
  console.error('  p8-file:   Path to your AuthKey_XXXXXX.p8 file');
  console.error('  key-id:    Key ID from ASC (e.g. ABC123DEFG)');
  console.error('  issuer-id: Issuer ID from ASC (e.g. 12345678-1234-1234-1234-123456789012)');
  console.error('  app-id:    Your app numeric ID from ASC');
  process.exit(1);
}

// Build JWT
function makeJWT() {
  const privateKey = fs.readFileSync(p8Path, 'utf8');
  const now = Math.floor(Date.now() / 1000);

  const header = Buffer.from(JSON.stringify({
    alg: 'ES256',
    kid: keyId,
    typ: 'JWT'
  })).toString('base64url');

  const payload = Buffer.from(JSON.stringify({
    iss: issuerId,
    iat: now,
    exp: now + 1200,
    aud: 'appstoreconnect-v1'
  })).toString('base64url');

  const signInput = `${header}.${payload}`;
  const sign = crypto.createSign('SHA256');
  sign.update(signInput);
  const sig = sign.sign(privateKey);

  // Convert DER signature to raw r||s format for ES256
  const rLen = sig[3];
  let r = sig.slice(4, 4 + rLen);
  let sLen = sig[4 + rLen + 1];
  let s = sig.slice(4 + rLen + 2, 4 + rLen + 2 + sLen);
  // Trim leading zeros
  if (r.length > 32) r = r.slice(r.length - 32);
  if (s.length > 32) s = s.slice(s.length - 32);
  // Pad if needed
  if (r.length < 32) r = Buffer.concat([Buffer.alloc(32 - r.length), r]);
  if (s.length < 32) s = Buffer.concat([Buffer.alloc(32 - s.length), s]);

  const rawSig = Buffer.concat([r, s]).toString('base64url');
  return `${signInput}.${rawSig}`;
}

async function run() {
  const token = makeJWT();
  const url = `https://api.appstoreconnect.apple.com/v1/apps/${appId}`;
  const notificationUrl = 'https://equiedge-scraper.vercel.app/api/apple-notifications';

  console.log(`Setting sandbox URL to: ${notificationUrl}`);
  console.log(`App ID: ${appId}\n`);

  const res = await fetch(url, {
    method: 'PATCH',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      data: {
        type: 'apps',
        id: appId,
        attributes: {
          subscriptionStatusUrlForSandbox: notificationUrl,
        }
      }
    })
  });

  const body = await res.text();
  if (res.ok) {
    console.log('Success! Sandbox Server URL has been set.');
  } else {
    console.error(`Failed with status ${res.status}:`);
    console.error(body);
  }
}

run().catch(console.error);
