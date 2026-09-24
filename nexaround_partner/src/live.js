import { useEffect, useEffectEvent } from 'react';
import { API_BASE } from './api';

/**
 * Live updates from GET /partner/events, so the portal changes under the
 * vendor's eyes instead of on the next reload.
 *
 * Read with fetch rather than EventSource: EventSource cannot send the
 * Authorization header, and the alternative — the token in the query string —
 * would land in the nginx access log.
 *
 * The shell opens one stream per tab and re-broadcasts every event on window
 * (the same pattern as api.js's auth:unauthorized), so a page listens with
 * `useLiveEvent` without callbacks threaded through props.
 */

const LIVE_EVENT = 'partner:live';

// Sent instead of 'ready' when a stream comes back after a drop. Events
// published while it was down are gone (Redis pub/sub keeps nothing), so every
// page treats this as "something changed" and re-reads what it shows.
export const RESYNC = 'resync';

// The server sends a heartbeat every 20 s. Silence for this long means the
// connection died without closing (a sleeping laptop, a proxy dropping it).
const WATCHDOG_MS = 50_000;
const MAX_BACKOFF_MS = 60_000;
const SESSION_EXPIRED = 'Session expired. Please sign in again.';

// One SSE frame: `event:` and `data:` lines. Heartbeats are comment lines
// (starting ':') with no data, and come back as null.
function parseFrame(frame) {
  let type = 'message';
  const data = [];
  for (const line of frame.split('\n')) {
    if (!line || line.startsWith(':')) continue;
    const colon = line.indexOf(':');
    const field = colon === -1 ? line : line.slice(0, colon);
    let value = colon === -1 ? '' : line.slice(colon + 1);
    if (value.startsWith(' ')) value = value.slice(1);
    if (field === 'event') type = value;
    else if (field === 'data') data.push(value);
  }
  if (!data.length) return null;
  try {
    return { type, data: JSON.parse(data.join('\n')) };
  } catch {
    return null;
  }
}

/**
 * Keep a stream open until the returned stop function is called, reconnecting
 * with backoff after any drop. `onSessionEnded(message)` fires once, when the
 * server says the session is over (expired, logged out, suspended); nothing
 * reconnects after it.
 */
export function connectLiveStream({ onEvent, onSessionEnded }) {
  let stopped = false;
  let controller = null;
  let retryTimer = null;
  let waiting = false;
  let attempt = 0;
  let connectedBefore = false;

  const retryLater = () => {
    if (stopped) return;
    // Full jitter, so every tab of every vendor does not reconnect in the
    // same second after an API restart.
    const ceiling = Math.min(MAX_BACKOFF_MS, 1000 * 2 ** attempt);
    attempt += 1;
    waiting = true;
    retryTimer = setTimeout(run, ceiling / 2 + Math.random() * (ceiling / 2));
  };

  const end = (message) => {
    stopped = true;
    onSessionEnded(message || SESSION_EXPIRED);
  };

  async function run() {
    waiting = false;
    const token = localStorage.getItem('partner_token');
    if (stopped || !token) return;

    controller = new AbortController();
    const { signal } = controller;
    let watchdog = null;
    const feed = () => {
      clearTimeout(watchdog);
      watchdog = setTimeout(() => controller.abort(), WATCHDOG_MS);
    };

    try {
      feed();
      const res = await fetch(`${API_BASE}/partner/events`, {
        headers: { Authorization: `Bearer ${token}`, Accept: 'text/event-stream' },
        cache: 'no-store',
        signal,
      });
      // 401 is a dead token; 403 is a disabled login or suspended vendor.
      // Either way the portal is unusable, and the server's words say why.
      if (res.status === 401 || res.status === 403) {
        let message = SESSION_EXPIRED;
        if (res.status === 403) {
          try { message = (await res.json()).detail || message; } catch { /* keep default */ }
        }
        end(message);
        return;
      }
      if (!res.ok || !res.body) throw new Error(`Live updates: HTTP ${res.status}`);

      const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
      let buffer = '';
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        feed();
        buffer += value;
        let split;
        while ((split = buffer.indexOf('\n\n')) !== -1) {
          const event = parseFrame(buffer.slice(0, split));
          buffer = buffer.slice(split + 2);
          if (!event) continue;
          if (event.type === 'session.ended') {
            end(event.data?.message);
            return;
          }
          if (event.type === 'ready') {
            attempt = 0;
            onEvent(connectedBefore ? RESYNC : 'ready', {});
            connectedBefore = true;
            continue;
          }
          onEvent(event.type, event.data || {});
        }
      }
    } catch {
      // Network drop, watchdog abort, 429 or 5xx: all retried below.
    } finally {
      clearTimeout(watchdog);
    }
    retryLater();
  }

  // Back online, or back to a tab the browser may have throttled: do not sit
  // out the rest of a long backoff.
  const wake = () => {
    if (!waiting || stopped) return;
    clearTimeout(retryTimer);
    attempt = 0;
    run();
  };
  const onVisible = () => { if (document.visibilityState === 'visible') wake(); };
  window.addEventListener('online', wake);
  document.addEventListener('visibilitychange', onVisible);

  run();

  return () => {
    stopped = true;
    clearTimeout(retryTimer);
    controller?.abort();
    window.removeEventListener('online', wake);
    document.removeEventListener('visibilitychange', onVisible);
  };
}

export function broadcastLive(type, data) {
  window.dispatchEvent(new CustomEvent(LIVE_EVENT, { detail: { type, data } }));
}

/** Run `handler({ type, data })` whenever one of `types` arrives. */
export function useLiveEvent(types, handler) {
  const onEvent = useEffectEvent(handler);
  const key = [].concat(types).join(' ');
  useEffect(() => {
    const wanted = new Set(key.split(' '));
    const listener = (e) => {
      if (wanted.has(e.detail.type)) onEvent(e.detail);
    };
    window.addEventListener(LIVE_EVENT, listener);
    return () => window.removeEventListener(LIVE_EVENT, listener);
  }, [key]);
}

// ── Desktop notifications ────────────────────────────────────────────────────
// For a vendor who keeps the portal in a background tab. Opt-in from the
// sidebar: browsers only show the permission prompt reliably after a click.

export const desktopAlertsPermission = () =>
  (typeof window !== 'undefined' && 'Notification' in window ? Notification.permission : 'unsupported');

export function showDesktopAlert({ title, body, tag, onClick }) {
  if (desktopAlertsPermission() !== 'granted') return;
  try {
    // `tag` collapses the copies that each open tab would otherwise show.
    const n = new Notification(title, { body, tag, icon: '/logo_2.png' });
    n.onclick = () => {
      window.focus();
      onClick?.();
      n.close();
    };
  } catch {
    // Android Chrome only allows notifications from a service worker, and
    // throws here. The in-page alert still shows.
  }
}
