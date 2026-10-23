import { useEffect, useState } from 'react';
import { apiGet } from './api';

// The server time of the last check, so a pop-up shows each event once. Per
// browser: an admin with two tabs open gets each pop-up in one of them.
const SINCE_KEY = 'enquiry_alerts_since';
// Fired after the admin changes a request, so the badge follows at once.
const CHANGED = 'enquiries-changed';

export const notifyEnquiriesChanged = () => window.dispatchEvent(new Event(CHANGED));

const readSince = () => {
  try { return localStorage.getItem(SINCE_KEY); } catch { return null; }
};
const writeSince = (value) => {
  try { localStorage.setItem(SINCE_KEY, value); } catch { /* private window */ }
};

/**
 * The Enquiries badge (requests still open) and pop-ups for what happened
 * since the last check: new requests and vendors' answers from the portal.
 * Polled every 30 seconds.
 */
export function useEnquiryAlerts() {
  const [open, setOpen] = useState(null);
  const [popups, setPopups] = useState([]);

  useEffect(() => {
    let active = true;
    const load = async () => {
      const since = readSince();
      try {
        const res = await apiGet(
          `/admin/experiences/enquiries/alerts${since ? `?since=${encodeURIComponent(since)}` : ''}`,
        );
        if (!active) return;
        setOpen(res.open);
        // The first check only sets the clock: no pop-ups for the backlog.
        if (since && res.events.length) {
          setPopups((prev) => [
            ...res.events.filter((ev) => !prev.some((p) => p.id === ev.id && p.kind === ev.kind)),
            ...prev,
          ].slice(0, 4));
        }
        writeSince(res.now);
      } catch { /* offline: try again next time */ }
    };
    load();
    const timer = setInterval(load, 30000);
    window.addEventListener(CHANGED, load);
    return () => {
      active = false;
      clearInterval(timer);
      window.removeEventListener(CHANGED, load);
    };
  }, []);

  const dismiss = (ev) => setPopups((prev) => prev.filter((p) => p !== ev));
  return { open, popups, dismiss };
}
