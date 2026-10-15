// Blocked-date ranges for a package, as the API stores them: a list of
// inclusive ISO ranges, [{ start: '2026-11-01', end: '2026-11-05' }]. A single
// day is a range whose start and end are the same. Anything not covered is
// available. ISO dates compare correctly as plain strings, and are handled as
// UTC below so a timezone can never shift a day.

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const toDate = (iso) => {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d));
};
const toIso = (date) => date.toISOString().slice(0, 10);

export const addDays = (iso, n) => {
  const date = toDate(iso);
  date.setUTCDate(date.getUTCDate() + n);
  return toIso(date);
};

/** Today in the viewer's own calendar, as ISO. */
export const todayIso = () => {
  const now = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
};

/** '2026-11-05' -> '5 Nov 2026' */
export const formatDay = (iso) => {
  const [y, m, d] = iso.split('-').map(Number);
  return `${d} ${MONTHS[m - 1]} ${y}`;
};

/** Sorted, with overlapping and touching ranges joined (Nov 1-3 + Nov 4-6 = one). */
export const mergeRanges = (ranges) => {
  const sorted = (ranges || [])
    .map((r) => (r.end < r.start ? { start: r.end, end: r.start } : { start: r.start, end: r.end }))
    .sort((a, b) => (a.start < b.start ? -1 : a.start > b.start ? 1 : 0));
  const out = [];
  sorted.forEach((r) => {
    const last = out[out.length - 1];
    if (last && r.start <= addDays(last.end, 1)) {
      if (r.end > last.end) last.end = r.end;
    } else {
      out.push({ ...r });
    }
  });
  return out;
};

/** Block everything from `a` to `b`, in either order, both days included. */
export const addRange = (ranges, a, b) =>
  mergeRanges([...(ranges || []), { start: a < b ? a : b, end: a < b ? b : a }]);

export const isBlocked = (ranges, day) =>
  (ranges || []).some((r) => r.start <= day && day <= r.end);

/** Make one day available again, splitting a range around it if needed. */
export const removeDate = (ranges, day) => {
  const out = [];
  (ranges || []).forEach((r) => {
    if (!(r.start <= day && day <= r.end)) {
      out.push({ ...r });
      return;
    }
    if (r.start < day) out.push({ start: r.start, end: addDays(day, -1) });
    if (day < r.end) out.push({ start: addDays(day, 1), end: r.end });
  });
  return out;
};

/** Days in the month of 'YYYY-MM', and which weekday (0 = Sunday) it starts on. */
export const monthShape = (ym) => {
  const [y, m] = ym.split('-').map(Number);
  return {
    days: new Date(Date.UTC(y, m, 0)).getUTCDate(),
    startsOn: new Date(Date.UTC(y, m - 1, 1)).getUTCDay(),
    label: `${['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][m - 1]} ${y}`,
  };
};

export const shiftMonth = (ym, delta) => {
  const [y, m] = ym.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1 + delta, 1));
  return toIso(date).slice(0, 7);
};
