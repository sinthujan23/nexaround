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
  time_here: '', price: '', access_note: '', body_md: '', links: [],
});

export const newMove = (mode = 'walk') => ({
  id: newId(), type: 'move', mode, title: '', duration: '', cost: '', access_note: '', body_md: '', links: [],
});

export const newBreak = () => ({
  id: newId(), type: 'break', title: 'Lunch / Rest', duration: '45 min', access_note: '', body_md: '', links: [],
});

export const newDay = (first = false) => ({
  id: newId(), title: '', starts_at: '09:00', steps: first ? [newStop()] : [],
});

export const emptyGuide = () => ({
  city: '', country: '', title: '', summary: '', cover_url: '', duration: '', budget: '',
  intro_md: '', days: [newDay(true)],
});

// The one day of a guide saved before days existed (city_tours.LEGACY_DAY_ID).
const LEGACY_DAY_ID = '00000000-0000-4000-8000-000000000001';

/** A guide with days: one saved before days existed is one day of its steps. */
export function withDays(content) {
  if (!content || Array.isArray(content.days)) return content;
  const { steps, ...rest } = content;
  return { ...rest, days: [{ id: LEGACY_DAY_ID, title: '', starts_at: '', steps: steps || [] }] };
}

export const allSteps = (content) => (content?.days || []).flatMap((d) => d.steps || []);

/** Stop numbers by step id, as the app numbers them: from 1 on each day. */
export function stopNumbers(steps) {
  const numbers = {};
  let n = 0;
  steps.forEach((s) => { if (s.type === 'stop') numbers[s.id] = ++n; });
  return numbers;
}

// ── Planned minutes: a copy of city_tour_trips.parse_minutes on the server ──
// The server's numbers are the ones the app plans with; this only lets the
// editor and the preview show times before a save. Keep the two in step.

const WORDS = [
  [/\bhalf[ -](?:an )?hour\b/g, '30 min'],
  [/\b(?:an|one) hour\b/g, '1 hour'],
  [/\bquarter of an hour\b/g, '15 min'],
  [/(\d+):(\d{2})\b/g, '$1 h $2 min'],
  [/½/g, '.5'],
];
const RANGE = /\s*(?:–|—|-|\bto\b|\bor\b)\s*/;
const AMOUNT = /(\d+(?:[.,]\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m)?(?![a-z])/g;
const unitOf = (word) => (word ? (word[0] === 'h' ? 'h' : 'm') : null);

function side(text, defaultUnit) {
  let total = null;
  let last = null;
  for (const [, number, word] of text.matchAll(AMOUNT)) {
    let unit = unitOf(word);
    if (unit === null) unit = last === 'h' ? 'm' : defaultUnit;
    if (unit === null) return null;
    total = (total || 0) + parseFloat(number.replace(',', '.')) * (unit === 'h' ? 60 : 1);
    last = unit;
  }
  return total;
}

/** "20 min" → 20, "1.5–2 hours" → 105, "2 hr 45 min" → 165; null when unreadable. */
export function parseMinutes(input) {
  let text = (input || '').trim().toLowerCase();
  if (!text) return null;
  for (const [pattern, repl] of WORDS) text = text.replace(pattern, repl);
  const first = [...text.matchAll(AMOUNT)].map((m) => m[2]).find(Boolean) || '';
  const defaultUnit = unitOf(first);
  const values = text.split(RANGE).map((part) => side(part, defaultUnit)).filter((v) => v);
  if (!values.length) return null;
  const middle = (Math.min(...values) + Math.max(...values)) / 2;
  return Math.min(12 * 60, Math.max(5, Math.floor(middle / 5 + 0.5) * 5));
}

const DEFAULT_MINUTES = { stop: 30, move: 15, break: 45 };

export const stepMinutes = (step) =>
  parseMinutes(step.type === 'stop' ? step.time_here : step.duration) || DEFAULT_MINUTES[step.type] || 30;

/** "09:00" → 540; null for none. */
export const clockMinutes = (hhmm) => {
  const m = /^(\d{1,2}):(\d{2})$/.exec(hhmm || '');
  return m ? Number(m[1]) * 60 + Number(m[2]) : null;
};

/** 540 → "9:00 AM", as the preview shows a time. */
export function formatClock(minutes) {
  const total = ((minutes % 1440) + 1440) % 1440;
  const h = Math.floor(total / 60);
  const m = total % 60;
  return `${h % 12 || 12}:${String(m).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
}

/** A day laid out from its start: { times: {stepId: [start, end]}, start, end,
 * minutes }, in minutes from midnight; times are empty with no start time. */
export function dayPlan(day) {
  const start = clockMinutes(day?.starts_at);
  const times = {};
  let cursor = start ?? 0;
  let minutes = 0;
  for (const step of day?.steps || []) {
    const length = stepMinutes(step);
    if (start !== null) times[step.id] = [cursor, cursor + length];
    cursor += length;
    minutes += length;
  }
  return { times, start, end: start === null ? null : start + minutes, minutes };
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
