import type { Guide } from './guides';

// Festival dates. Dates are stored as UTC midnight and always shown in UTC,
// so a date never slips a day with the reader's or the server's time zone.

export interface EventDate { start: Date; end?: Date; note?: string }

const fmt = (d: Date, o: Intl.DateTimeFormatOptions) => d.toLocaleDateString('en-GB', { ...o, timeZone: 'UTC' });

/** "6 Feb 2027", "5–14 Feb 2027", "30 Jan – 2 Feb 2027", "29 Dec 2026 – 2 Jan 2027". */
export function formatRange(start: Date, end?: Date): string {
  if (!end || end.getTime() === start.getTime()) return fmt(start, { day: 'numeric', month: 'short', year: 'numeric' });
  const sameYear = start.getUTCFullYear() === end.getUTCFullYear();
  const sameMonth = sameYear && start.getUTCMonth() === end.getUTCMonth();
  if (sameMonth) return `${start.getUTCDate()}–${fmt(end, { day: 'numeric', month: 'short', year: 'numeric' })}`;
  if (sameYear) return `${fmt(start, { day: 'numeric', month: 'short' })} – ${fmt(end, { day: 'numeric', month: 'short', year: 'numeric' })}`;
  return `${fmt(start, { day: 'numeric', month: 'short', year: 'numeric' })} – ${fmt(end, { day: 'numeric', month: 'short', year: 'numeric' })}`;
}

/** The first date that hasn't ended yet, on `now`. */
export function nextDate(dates: EventDate[], now = new Date()): EventDate | undefined {
  const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  return [...dates].sort((a, b) => +a.start - +b.start).find((d) => +(d.end ?? d.start) >= today);
}

/** Dates for the page's script, which works out "in 23 days" in the reader's browser. */
export const datesJson = (dates: EventDate[]) =>
  JSON.stringify(dates.map((d) => ({ s: d.start.toISOString().slice(0, 10), e: (d.end ?? d.start).toISOString().slice(0, 10), t: formatRange(d.start, d.end) })));

export const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

export const isEvent = (g: Guide) => !!g.data.event;

/** Colour for each continent on the festival calendar (card stubs, timeline dots, chips). */
export const CONTINENT_COLOR: Record<string, string> = {
  Africa: '#f5a300',
  Asia: '#ff6b4a',
  Europe: '#6c7dff',
  'North America': '#e8458b',
  'South America': '#1fbf75',
  Oceania: '#00b5b8',
};
export const continentColor = (c: string) => CONTINENT_COLOR[c] ?? '#ff6b4a';

/** Build-time stand-in for the countdown the reader's browser shows ("In 75 days"). */
export function countdownText(start: Date, now = new Date()): string {
  const days = Math.ceil((+start - now.getTime()) / 864e5);
  if (days <= 0) return 'On now';
  if (days === 1) return 'Tomorrow';
  if (days < 60) return `In ${days} days`;
  return `In ${Math.round(days / 30.44)} months`;
}
