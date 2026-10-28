import { useEffect, useState } from 'react';
import { apiGet } from './api';

// City Tours: step-by-step city guides. A guide is one document (see the
// server's app/services/city_tours.py for its shape); the editor edits it, the
// phone preview draws it as the app will, and an admin approves each version
// before travellers see it.

export const STATUS = {
  draft: { label: 'Draft', tone: 'ghost' },
  pending: { label: 'Waiting for review', tone: 'yellow' },
  changes_requested: { label: 'Sent back', tone: 'red' },
  approved: { label: 'Live', tone: 'green' },
};

/** The pills a guide's row and header show. */
export function tourBadges(t) {
  const badges = [];
  if (t.review_status === 'approved') {
    badges.push(t.is_hidden ? { label: 'Hidden from the app', tone: 'ghost' } : STATUS.approved);
    return badges;
  }
  badges.push(STATUS[t.review_status] || STATUS.draft);
  if (t.is_live) {
    badges.push(t.is_hidden
      ? { label: 'Hidden from the app', tone: 'ghost' }
      : { label: 'Older version live', tone: 'green' });
  }
  return badges;
}

// How a traveller gets to the next stop, with the Material icon the app
// draws for it (city_tour_widgets.dart → cityTourModeIcon).
export const MODES = [
  { key: 'walk', label: 'Walk', icon: 'directions_walk' },
  { key: 'metro', label: 'Metro', icon: 'subway' },
  { key: 'bus', label: 'Bus', icon: 'directions_bus' },
  { key: 'tram', label: 'Tram', icon: 'tram' },
  { key: 'train', label: 'Train', icon: 'train' },
  { key: 'taxi', label: 'Taxi or ride app', icon: 'local_taxi' },
  { key: 'tuk_tuk', label: 'Tuk-tuk', icon: 'electric_rickshaw' },
  { key: 'boat', label: 'Boat or ferry', icon: 'directions_boat' },
  { key: 'bike', label: 'Bike', icon: 'directions_bike' },
  { key: 'car', label: 'Car or transfer', icon: 'directions_car' },
];

export const modeOf = (key) => MODES.find((m) => m.key === key) || MODES[0];

/** Partner logos, copied from the app's assets so the preview shows the same. */
export const partnerLogo = (key) => `/partners/${key}_logo.png`;

/** A v4 id. crypto.randomUUID needs https; the panel may be opened without it. */
export function newId() {
  if (window.crypto?.randomUUID) return window.crypto.randomUUID();
  const b = window.crypto.getRandomValues(new Uint8Array(16));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

export const newStop = () => ({
  id: newId(), type: 'stop', name: '', lat: null, lng: null, photo_url: '',
  time_here: '', price: '', body_md: '', links: [],
});

export const newMove = (mode = 'walk') => ({
  id: newId(), type: 'move', mode, title: '', duration: '', cost: '', body_md: '', links: [],
});

export const emptyGuide = () => ({
  city: '', country: '', title: '', summary: '', cover_url: '', duration: '', budget: '',
  intro_md: '', steps: [newStop()],
});

/** Stop numbers by step id, as the app numbers them. */
export function stopNumbers(steps) {
  const numbers = {};
  let n = 0;
  steps.forEach((s) => { if (s.type === 'stop') numbers[s.id] = ++n; });
  return numbers;
}

// Fired after a review decision, so the sidebar badge follows at once.
const CHANGED = 'city-tours-changed';

export const notifyCityToursChanged = () => window.dispatchEvent(new Event(CHANGED));

/** How many guides wait for an admin, refreshed every minute. Admins only. */
export function useCityTourCount() {
  const [count, setCount] = useState(null);
  useEffect(() => {
    let active = true;
    const load = () => apiGet('/admin/city-tours/count')
      .then((c) => { if (active) setCount(c.pending); })
      .catch(() => {});
    load();
    const timer = setInterval(load, 60000);
    window.addEventListener(CHANGED, load);
    return () => {
      active = false;
      clearInterval(timer);
      window.removeEventListener(CHANGED, load);
    };
  }, []);
  return count;
}
