#!/usr/bin/env node
// Sets up subscription metadata in App Store Connect via API
// Usage: node setup-asc-subscriptions.js

const fs = require('fs');
const crypto = require('crypto');

const p8Path = 'AuthKey_9F26GWG48F.p8';
const keyId = '9F26GWG48F';
const issuerId = '40f3b900-4f81-4b0c-85fd-46f946494bf5';
const appId = '6761791989';

const BASE = 'https://api.appstoreconnect.apple.com';

// Subscription IDs from ASC
const subs = [
  { id: '6762592280', name: 'Basic Monthly', displayName: 'Basic Monthly', desc: '10 track-day analyses per week', price: '14.99' },
  { id: '6762592423', name: 'Basic Annual',  displayName: 'Basic Annual',  desc: '10 track-day analyses per week — save 20%', price: '143.99' },
  { id: '6762592877', name: 'Pro Monthly',   displayName: 'Pro Monthly',   desc: 'Unlimited track-day analyses', price: '34.99' },
  { id: '6762592730', name: 'Pro Annual',    displayName: 'Pro Annual',    desc: 'Unlimited analyses — save 17%', price: '347.99' },
];

function makeJWT() {
  const privateKey = fs.readFileSync(p8Path, 'utf8');
  const now = Math.floor(Date.now() / 1000);
  const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: keyId, typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({ iss: issuerId, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' })).toString('base64url');
  const signInput = `${header}.${payload}`;
  const sign = crypto.createSign('SHA256');
  sign.update(signInput);
  const sig = sign.sign(privateKey);
  const rLen = sig[3];
  let r = sig.slice(4, 4 + rLen);
  let sLen = sig[4 + rLen + 1];
  let s = sig.slice(4 + rLen + 2, 4 + rLen + 2 + sLen);
  if (r.length > 32) r = r.slice(r.length - 32);
  if (s.length > 32) s = s.slice(s.length - 32);
  if (r.length < 32) r = Buffer.concat([Buffer.alloc(32 - r.length), r]);
  if (s.length < 32) s = Buffer.concat([Buffer.alloc(32 - s.length), s]);
  return `${signInput}.${Buffer.concat([r, s]).toString('base64url')}`;
}

async function api(method, path, body) {
  const token = makeJWT();
  const opts = {
    method,
    headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
  };
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(`${BASE}${path}`, opts);
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = text; }
  return { status: res.status, ok: res.ok, data: json };
}

async function addLocalization(subId, displayName, description) {
  // Check existing localizations first
  const existing = await api('GET', `/v1/subscriptions/${subId}/subscriptionLocalizations`);
  if (existing.ok && existing.data.data && existing.data.data.length > 0) {
    console.log(`  Localization already exists, updating...`);
    const locId = existing.data.data[0].id;
    const res = await api('PATCH', `/v1/subscriptionLocalizations/${locId}`, {
      data: {
        type: 'subscriptionLocalizations',
        id: locId,
        attributes: { name: displayName, description: description }
      }
    });
    return res;
  }

  return api('POST', '/v1/subscriptionLocalizations', {
    data: {
      type: 'subscriptionLocalizations',
      attributes: {
        name: displayName,
        description: description,
        locale: 'en-AU',
      },
      relationships: {
        subscription: {
          data: { type: 'subscriptions', id: subId }
        }
      }
    }
  });
}

async function setPrice(subId, targetPrice) {
  // Check if price already exists
  const existingPrices = await api('GET', `/v1/subscriptions/${subId}/prices?include=subscriptionPricePoint`);
  if (existingPrices.ok && existingPrices.data.data && existingPrices.data.data.length > 0) {
    console.log(`  Price already set, skipping`);
    return { ok: true, status: 200 };
  }

  // Find the AUS price point matching target price
  let pricePointId = null;
  let url = `/v1/subscriptions/${subId}/pricePoints?filter[territory]=AUS&limit=200`;

  while (url && !pricePointId) {
    const res = await api('GET', url);
    if (!res.ok) {
      console.log(`  Failed to fetch price points: ${res.status}`);
      return res;
    }
    for (const pp of res.data.data) {
      if (pp.attributes.customerPrice === targetPrice) {
        pricePointId = pp.id;
        break;
      }
    }
    // Check for next page
    url = res.data.links?.next ? res.data.links.next.replace(BASE, '') : null;
  }

  if (!pricePointId) {
    console.log(`  Could not find AUS price point for $${targetPrice}`);
    // List available prices for debugging
    const debugRes = await api('GET', `/v1/subscriptions/${subId}/pricePoints?filter[territory]=AUS&limit=10`);
    if (debugRes.ok) {
      console.log(`  Sample prices available:`);
      for (const pp of debugRes.data.data.slice(0, 5)) {
        console.log(`    $${pp.attributes.customerPrice} (id: ${pp.id})`);
      }
    }
    return { ok: false, status: 404 };
  }

  console.log(`  Found price point: ${pricePointId} for $${targetPrice}`);

  // Create the subscription price
  return api('POST', '/v1/subscriptionPrices', {
    data: {
      type: 'subscriptionPrices',
      attributes: {
        startDate: null, // effective immediately
        preserveCurrentPrice: false,
      },
      relationships: {
        subscription: {
          data: { type: 'subscriptions', id: subId }
        },
        subscriptionPricePoint: {
          data: { type: 'subscriptionPricePoints', id: pricePointId }
        }
      }
    }
  });
}

async function run() {
  console.log('=== Setting up ASC Subscription Metadata ===\n');

  // Step 1: Add localizations
  for (const sub of subs) {
    console.log(`\n[${sub.name}] Adding localization...`);
    const res = await addLocalization(sub.id, sub.displayName, sub.desc);
    console.log(`  ${res.ok ? 'OK' : 'FAILED'} (${res.status})`);
    if (!res.ok) console.log(`  ${JSON.stringify(res.data?.errors?.[0] || res.data)}`);
  }

  // Step 2: Set prices
  for (const sub of subs) {
    console.log(`\n[${sub.name}] Setting price $${sub.price} AUD...`);
    const res = await setPrice(sub.id, sub.price);
    console.log(`  ${res.ok ? 'OK' : 'FAILED'} (${res.status})`);
    if (!res.ok && res.data?.errors) console.log(`  ${JSON.stringify(res.data.errors[0])}`);
  }

  // Step 3: Check subscription states
  console.log('\n\n=== Checking subscription states ===');
  const subsRes = await api('GET', `/v1/subscriptionGroups/22042103/subscriptions`);
  if (subsRes.ok) {
    for (const s of subsRes.data.data) {
      console.log(`  ${s.attributes.name} (${s.attributes.productId}): ${s.attributes.state}`);
    }
  }

  // Step 4: Try setting notification URL
  console.log('\n\n=== Setting notification URLs ===');
  const notifUrl = 'https://equiedge-scraper.vercel.app/api/apple-notifications';

  const urlRes = await api('PATCH', `/v1/apps/${appId}`, {
    data: {
      type: 'apps',
      id: appId,
      attributes: {
        subscriptionStatusUrl: notifUrl,
        subscriptionStatusUrlVersion: 'V2',
        subscriptionStatusUrlForSandbox: notifUrl,
        subscriptionStatusUrlVersionForSandbox: 'V2',
      }
    }
  });

  if (urlRes.ok) {
    console.log('  SUCCESS! Both notification URLs set.');
  } else {
    console.log(`  Failed (${urlRes.status}):`);
    for (const err of (urlRes.data?.errors || [])) {
      console.log(`    ${err.source?.pointer}: ${err.code}`);
    }
  }

  console.log('\n=== Done ===');
}

run().catch(console.error);
