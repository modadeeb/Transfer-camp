// Firebase Cloud Messaging (HTTP v1) from a Worker, with a service-account JWT signed by WebCrypto.
// Secret FCM_SERVICE_ACCOUNT = the full service-account JSON downloaded from Firebase.
let cached = null; // { token, exp, email }

const b64url = (data) => {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};

export function fcmConfigured(env) {
  return Boolean(env.FCM_SERVICE_ACCOUNT);
}

function account(env) {
  const sa = typeof env.FCM_SERVICE_ACCOUNT === 'string' ? JSON.parse(env.FCM_SERVICE_ACCOUNT) : env.FCM_SERVICE_ACCOUNT;
  if (!sa?.client_email || !sa?.private_key || !sa?.project_id) throw new Error('FCM_SERVICE_ACCOUNT is incomplete');
  return sa;
}

async function accessToken(env) {
  const sa = account(env);
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.email === sa.client_email && cached.exp - 60 > now) return cached.token;

  const pem = sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (ch) => ch.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );
  const signature = b64url(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${claims}`)));
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}&assertion=${header}.${claims}.${signature}`,
  });
  if (!res.ok) throw new Error(`FCM auth failed: ${res.status}`);
  const json = await res.json();
  cached = { token: json.access_token, exp: now + Number(json.expires_in || 3600), email: sa.client_email };
  return cached.token;
}

/**
 * Sends a data-only web push (our service worker shows it).
 * @returns {'ok'|'invalid'|'error'} 'invalid' means the device token should be removed.
 */
export async function sendPush(env, token, { title, body, link, tag }) {
  const sa = account(env);
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${await accessToken(env)}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message: {
        token,
        data: { title: title || '', body: body || '', link: link || '/', tag: tag || '' },
        webpush: { headers: { Urgency: 'high', TTL: '86400' } },
        // The Flutter app (Android) needs a notification block so the system shows it when the app is closed.
        android: {
          priority: 'high',
          ttl: '86400s',
          notification: { title: title || '', body: body || '', channel_id: 'camp', tag: tag || undefined, click_action: 'FLUTTER_NOTIFICATION_CLICK' },
        },
      },
    }),
  });
  if (res.ok) return 'ok';
  if (res.status === 404 || res.status === 400) {
    const text = await res.text();
    if (/UNREGISTERED|INVALID_ARGUMENT|registration-token-not-registered/i.test(text)) return 'invalid';
  }
  return 'error';
}
