// Small helpers the two security pages share.

export const deviceLabel = (browser, os) => {
  if (browser && os) return `${browser} on ${os}`;
  return browser || os || 'Unknown device';
};

const TZ = 'Asia/Colombo';

// One calendar day in Sri Lanka time, so "Today" matches the clock on the wall.
export const dayKey = (iso) => new Date(iso).toLocaleDateString('en-CA', { timeZone: TZ });

export const dayLabel = (iso) => {
  const key = dayKey(iso);
  const now = Date.now();
  if (key === dayKey(now)) return 'Today';
  if (key === dayKey(now - 86400000)) return 'Yesterday';
  return new Date(iso).toLocaleDateString('en-GB', {
    weekday: 'short', day: 'numeric', month: 'short', year: 'numeric', timeZone: TZ,
  });
};

export const clock = (iso) => new Date(iso).toLocaleTimeString('en-US', {
  hour: 'numeric', minute: '2-digit', hour12: true, timeZone: TZ,
}).toLowerCase();

export const groupByDay = (items) => {
  const groups = [];
  for (const e of items) {
    const key = dayKey(e.occurred_at);
    const last = groups[groups.length - 1];
    if (last && last.key === key) last.items.push(e);
    else groups.push({ key, label: dayLabel(e.occurred_at), items: [e] });
  }
  return groups;
};
