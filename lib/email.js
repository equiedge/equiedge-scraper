// lib/email.js
// Email sending via Resend + HMAC token generation for review links.

const crypto = require('crypto');

const RESEND_API_URL = 'https://api.resend.com/emails';
const TOKEN_EXPIRY_MS = 14 * 24 * 60 * 60 * 1000; // 14 days

// Generate HMAC-SHA256 token for week|expiry
function generateReviewToken(week) {
  const secret = process.env.RESULTS_REVIEW_SECRET;
  if (!secret) throw new Error('RESULTS_REVIEW_SECRET not set');
  const exp = Date.now() + TOKEN_EXPIRY_MS;
  const payload = `${week}|${exp}`;
  const hmac = crypto.createHmac('sha256', secret).update(payload).digest('hex');
  return `${payload}|${hmac}`;
}

// Validate token. Returns { valid, week } or { valid: false, reason }
function validateReviewToken(token) {
  const secret = process.env.RESULTS_REVIEW_SECRET;
  if (!secret) return { valid: false, reason: 'No secret configured' };
  if (!token) return { valid: false, reason: 'No token provided' };

  const parts = token.split('|');
  if (parts.length !== 3) return { valid: false, reason: 'Invalid token format' };

  const [week, expStr, providedHmac] = parts;
  const exp = parseInt(expStr, 10);
  if (isNaN(exp)) return { valid: false, reason: 'Invalid expiry' };
  if (Date.now() > exp) return { valid: false, reason: 'Token expired' };

  const expectedHmac = crypto.createHmac('sha256', secret).update(`${week}|${expStr}`).digest('hex');
  if (!crypto.timingSafeEqual(Buffer.from(providedHmac, 'hex'), Buffer.from(expectedHmac, 'hex'))) {
    return { valid: false, reason: 'Invalid signature' };
  }

  return { valid: true, week };
}

// Send email via Resend API (no SDK, just fetch)
async function sendEmail({ to, subject, html }) {
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) throw new Error('RESEND_API_KEY not set');

  const res = await fetch(RESEND_API_URL, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: 'EquiEdge <onboarding@resend.dev>',
      to: Array.isArray(to) ? to : [to],
      subject,
      html,
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Resend API error (${res.status}): ${body}`);
  }

  return await res.json();
}

// Send the weekly results review email
async function sendResultsReadyEmail(week, summary, logger = console) {
  const adminEmail = process.env.ADMIN_EMAIL;
  if (!adminEmail) throw new Error('ADMIN_EMAIL not set');

  const token = generateReviewToken(week);
  const baseUrl = process.env.SITE_URL || 'https://equiedge-scraper.vercel.app';
  const reviewUrl = `${baseUrl}/admin/results-review.html?week=${encodeURIComponent(week)}&token=${encodeURIComponent(token)}`;

  const profitSign = summary.profit >= 0 ? '+' : '';
  const roiPct = (summary.roi * 100).toFixed(1);

  const html = `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 500px; margin: 0 auto; padding: 20px;">
      <h2 style="color: #0A0A0F; margin-bottom: 16px;">EquiEdge Results Ready</h2>
      <p style="color: #333; font-size: 16px; margin-bottom: 8px;"><strong>${week}</strong></p>
      <div style="background: #f5f5f5; border-radius: 8px; padding: 16px; margin-bottom: 20px;">
        <p style="margin: 4px 0; color: #333;">${summary.totalBets} bets &middot; ${summary.wins}W / ${summary.losses}L</p>
        <p style="margin: 4px 0; color: ${summary.profit >= 0 ? '#00DC82' : '#FF4757'}; font-weight: 600; font-size: 18px;">
          ${profitSign}$${summary.profit.toFixed(2)} (${profitSign}${roiPct}% ROI)
        </p>
      </div>
      <a href="${reviewUrl}" style="display: inline-block; background: #00DC82; color: #0A0A0F; text-decoration: none; padding: 14px 28px; border-radius: 8px; font-weight: 600; font-size: 16px;">
        Review & Approve
      </a>
      <p style="color: #888; font-size: 12px; margin-top: 20px;">This link expires in 14 days.</p>
    </div>
  `;

  await sendEmail({
    to: adminEmail,
    subject: `EquiEdge results ready — ${week}`,
    html,
  });

  logger.log && logger.log(`Review email sent to ${adminEmail} for ${week}`);
}

// Send failure notification
async function sendFailureEmail(week, error, logger = console) {
  const adminEmail = process.env.ADMIN_EMAIL;
  if (!adminEmail) {
    logger.log && logger.log('Cannot send failure email — ADMIN_EMAIL not set');
    return;
  }

  try {
    await sendEmail({
      to: adminEmail,
      subject: `EquiEdge weekly job failed — ${week}`,
      html: `
        <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 500px; margin: 0 auto; padding: 20px;">
          <h2 style="color: #FF4757;">Weekly Results Job Failed</h2>
          <p><strong>Week:</strong> ${week}</p>
          <p><strong>Error:</strong></p>
          <pre style="background: #f5f5f5; padding: 12px; border-radius: 6px; overflow-x: auto; font-size: 13px;">${error}</pre>
          <p style="color: #888; font-size: 12px; margin-top: 16px;">Run manually with ?manualWeek=${week}&force=1</p>
        </div>
      `,
    });
    logger.log && logger.log(`Failure email sent to ${adminEmail} for ${week}`);
  } catch (emailErr) {
    logger.log && logger.log(`Failed to send failure email: ${emailErr.message}`);
  }
}

module.exports = {
  generateReviewToken,
  validateReviewToken,
  sendResultsReadyEmail,
  sendFailureEmail,
  sendEmail,
};
