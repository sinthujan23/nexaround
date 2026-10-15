// Shared by the Audit Trail and Devices pages.

const TZ = 'Asia/Colombo';

/** "15 Oct 2026, 2:05 PM" in Sri Lanka time, like the rest of the panel. */
export function formatWhen(iso) {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleString('en-GB', {
    day: 'numeric', month: 'short', year: 'numeric',
    hour: 'numeric', minute: '2-digit', hour12: true, timeZone: TZ,
  });
}

/** "15 Oct 2026" */
export function formatDay(iso) {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: TZ });
}

/** "10:03 am" */
export function formatClock(iso) {
  if (!iso) return '';
  return new Date(iso).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true, timeZone: TZ }).toLowerCase();
}

/** "just now", "5 min ago", "3 h ago", "2 d ago". */
export function timeAgo(iso) {
  if (!iso) return '—';
  const secs = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (secs < 60) return 'just now';
  if (secs < 3600) return `${Math.floor(secs / 60)} min ago`;
  if (secs < 86400) return `${Math.floor(secs / 3600)} h ago`;
  return `${Math.floor(secs / 86400)} d ago`;
}

export function deviceLabel(browser, os) {
  if (browser && os) return `${browser} on ${os}`;
  return browser || os || 'Unknown device';
}

export const ACTOR_LABELS = { admin: 'Admin', vendor: 'Partner', anonymous: 'Unknown' };
export const ACTOR_TONES = { admin: 'blue', vendor: 'green', anonymous: 'red' };

export const CATEGORY_LABELS = {
  auth: 'Sign-in & security',
  change: 'Change',
  access: 'Sensitive view',
};

export const REVOKE_REASONS = {
  user: 'Signed out',
  admin: 'Signed out by an admin',
  password: 'Password changed',
};
