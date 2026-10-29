/* Service worker: offline app shell + web push (data messages sent by our Worker through FCM). */
import { cleanupOutdatedCaches, createHandlerBoundToURL, precacheAndRoute } from 'workbox-precaching';
import { NavigationRoute, registerRoute } from 'workbox-routing';

precacheAndRoute(self.__WB_MANIFEST);
cleanupOutdatedCaches();
// The API is never cached: money and personal data stay on the server only.
registerRoute(new NavigationRoute(createHandlerBoundToURL('/index.html'), { denylist: [/^\/api\//] }));

self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('push', (event) => {
  let data = {};
  try {
    const json = event.data ? event.data.json() : {};
    data = json.data || json.notification || json;
  } catch {
    data = { title: 'معسكر نقلة', body: event.data ? event.data.text() : '' };
  }
  event.waitUntil(
    self.registration.showNotification(data.title || 'معسكر نقلة', {
      body: data.body || '',
      tag: data.tag || undefined,
      renotify: Boolean(data.tag),
      dir: 'rtl',
      lang: 'ar',
      icon: '/icons/icon-192.png',
      badge: '/icons/badge-96.png',
      data: { link: data.link || '/' },
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const link = (event.notification.data && event.notification.data.link) || '/';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if ('focus' in client) {
          client.postMessage({ type: 'navigate', link });
          return client.focus();
        }
      }
      return self.clients.openWindow(link);
    }),
  );
});
