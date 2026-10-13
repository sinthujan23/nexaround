import { useEffect, useRef, useState } from 'react';
import { apiDelete, apiGet, apiPatch, apiPost } from './api';

/**
 * The Map Database: our own places and their status.
 *
 *   live      shown in the app
 *   pending   waiting in the Review queue
 *   hidden    taken out of the app by an admin; can be made live again
 *   rejected  a suggestion turned down; kept so Google can't add it back
 *
 * Details and status are changed separately (updatePlace / setPlaceStatus),
 * so saving an edit never approves or hides a place by accident.
 */

export const STATUS_LABELS = {
  live: 'Live',
  pending: 'Needs review',
  hidden: 'Hidden',
  rejected: 'Rejected',
};

// The dot colour classes already used for experiences (index.css .dot-*).
export const STATUS_DOT = {
  live: 'dot-live',
  pending: 'dot-new',
  hidden: 'dot-hidden',
  rejected: 'dot-spam',
};

export const SOURCE_LABELS = {
  google: 'Google',
  admin: 'Admin',
  user: 'App user',
  seed: 'Seed list',
  unknown: 'Older record',
};

// What an admin can pick when hiding or rejecting a place.
export const REASONS = [
  ['duplicate_location', 'Duplicate of another place'],
  ['closed', 'Closed permanently'],
  ['not_a_place', 'Not a real place'],
  ['wrong_location', 'Wrong location'],
  ['inappropriate', 'Inappropriate'],
  ['admin_hidden', 'Hidden by admin'],
  ['other', 'Other (write a note)'],
];

const REASON_TEXT = {
  ...Object.fromEntries(REASONS),
  other: 'Other',
  user_suggestion: 'Suggested from the app',
  legacy_inactive: 'Old switched-off copy',
  merged_restored: 'Restored when duplicates were merged',
  legacy_restored: 'Restored old record',
  reopened: 'Reopened for review',
};

export const reasonText = (code) => (code ? REASON_TEXT[code] || code.replace(/_/g, ' ') : '');

export const listPlaces = (params) => {
  const qs = new URLSearchParams();
  Object.entries(params).forEach(([k, v]) => {
    if (v !== undefined && v !== null && v !== '' && v !== false) qs.set(k, String(v));
  });
  return `/admin/attractions?${qs.toString()}`;
};

export const getPlace = (id) => apiGet(`/admin/attractions/${id}`);
export const nearbyPlaces = (id, radius = 150) => apiGet(`/admin/attractions/${id}/nearby?radius_m=${radius}`);
export const createPlace = (body) => apiPost('/admin/attractions', body);
export const updatePlace = (id, body) => apiPatch(`/admin/attractions/${id}`, body);
export const setPlaceStatus = (id, status, reason, note) =>
  apiPost(`/admin/attractions/${id}/status`, { status, reason: reason || null, note: note || null });
export const deletePlace = (id) => apiDelete(`/admin/attractions/${id}`);

/** The editable fields of a place, as the form holds them. */
export const placeToForm = (place) => ({
  name: place?.name || '',
  category_id: place?.category_id || '',
  latitude: place?.latitude ?? '',
  longitude: place?.longitude ?? '',
  address: place?.address || '',
  description: place?.description || '',
  history: place?.history || '',
  entry_fee: place?.entry_fee ?? 0,
  currency: place?.currency || 'USD',
  photo_urls: place?.photo_urls || [],
});

/** The request body for create / PATCH. */
export const formToBody = (form) => ({
  name: form.name.trim(),
  category_id: form.category_id || null,
  latitude: Number(form.latitude),
  longitude: Number(form.longitude),
  address: form.address || null,
  description: form.description || null,
  history: form.history || null,
  entry_fee: Number(form.entry_fee) || 0,
  currency: (form.currency || 'USD').toUpperCase(),
  photo_urls: form.photo_urls,
});

export const formsDiffer = (a, b) => JSON.stringify(formToBody(a)) !== JSON.stringify(formToBody(b));

const CHANGED = 'places:changed';

/** Tell the sidebar badge and open lists that a place's status changed. */
export const notifyPlacesChanged = () => window.dispatchEvent(new Event(CHANGED));

/** Calls `fn` whenever any page reports a place change. */
export function usePlacesChanged(fn) {
  const latest = useRef(fn);
  useEffect(() => { latest.current = fn; });
  useEffect(() => {
    const handler = () => latest.current();
    window.addEventListener(CHANGED, handler);
    return () => window.removeEventListener(CHANGED, handler);
  }, []);
}

/** Per-status counts, refreshed every minute and after any change. */
export function usePlaceCounts() {
  const [counts, setCounts] = useState(null);
  useEffect(() => {
    let active = true;
    const load = () => apiGet('/admin/attractions/counts')
      .then((c) => { if (active) setCounts(c); })
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
  return counts;
}

/** 38,101 -> "38k" for a small badge. */
export const compactCount = (n) => {
  if (n == null) return '';
  if (n >= 10000) return `${Math.floor(n / 1000)}k`;
  if (n >= 1000) return `${(n / 1000).toFixed(1).replace(/\.0$/, '')}k`;
  return String(n);
};

/** Escape text before it goes into a Leaflet popup's HTML. */
export const escapeHtml = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
}[c]));

const TZ = 'Asia/Colombo';
export const formatDate = (value) =>
  value
    ? new Date(value).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: TZ })
    : '—';
export const formatDateTime = (value) =>
  value
    ? new Date(value).toLocaleString('en-GB', {
      day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: TZ,
    })
    : '—';
