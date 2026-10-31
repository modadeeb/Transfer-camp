// Push notifications through Firebase Cloud Messaging.
// The server decides whether push is configured (GET /api/push/config).
import { get, post } from './api.js';

const TOKEN_KEY = 'camp-push-token';

export function pushSupported() {
  return typeof window !== 'undefined' && 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
}

export function isIos() {
  return /iphone|ipad|ipod/i.test(navigator.userAgent);
}

export function isStandalone() {
  return window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
}

export function pushState() {
  if (!pushSupported()) return isIos() && !isStandalone() ? 'install-first' : 'unsupported';
  if (Notification.permission === 'denied') return 'denied';
  if (Notification.permission === 'granted' && localStorage.getItem(TOKEN_KEY)) return 'on';
  return 'off';
}

/** Ask permission, get an FCM token for this device and register it. */
export async function enablePush() {
  if (!pushSupported()) return isIos() && !isStandalone() ? 'install-first' : 'unsupported';
  const config = await get('/push/config');
  if (!config.web) return 'not-configured';
  const permission = await Notification.requestPermission();
  if (permission !== 'granted') return 'denied';
  const registration = await navigator.serviceWorker.ready;
  const [{ initializeApp, getApps }, { getMessaging, getToken }] = await Promise.all([import('@firebase/app'), import('@firebase/messaging')]);
  const app = getApps()[0] || initializeApp(config.firebase);
  const token = await getToken(getMessaging(app), { vapidKey: config.vapidKey, serviceWorkerRegistration: registration });
  if (!token) return 'error';
  await post('/devices', { token, platform: navigator.userAgent.slice(0, 40) });
  localStorage.setItem(TOKEN_KEY, token);
  return 'on';
}

export async function disablePush() {
  const token = localStorage.getItem(TOKEN_KEY);
  if (token) {
    try {
      await post('/devices/remove', { token });
    } catch {
      /* already gone */
    }
  }
  localStorage.removeItem(TOKEN_KEY);
  return 'off';
}
