// Browser-side helpers shared by the interactive components. Preferences
// (saved guides, km or miles) live in localStorage on the reader's device;
// every access is wrapped because storage can be blocked.

export const MI_PER_KM = 0.621371;
export type Units = 'km' | 'mi';

const read = (key: string) => {
  try { return localStorage.getItem(key); } catch { return null; }
};
const write = (key: string, value: string) => {
  try { localStorage.setItem(key, value); } catch { /* storage blocked: keep it for this page only */ }
};

let unitsNow: Units = read('nxg-units') === 'mi' ? 'mi' : 'km';
export const getUnits = (): Units => unitsNow;
export function setUnits(u: Units) {
  unitsNow = u;
  write('nxg-units', u);
  document.dispatchEvent(new CustomEvent('nxg:units', { detail: u }));
}

const LOCALE: Record<string, string> = { en: 'en-US', es: 'es-ES', fr: 'fr-FR', de: 'de-DE', hi: 'hi-IN' };
const locale = () => LOCALE[document.documentElement.lang] ?? 'en-US';

export const fmtNum = (n: number, dec = 0) =>
  n.toLocaleString(locale(), { minimumFractionDigits: dec, maximumFractionDigits: dec });

export const fmtKm = (km: number, u: Units = unitsNow) =>
  u === 'mi' ? `${fmtNum(Math.round(km * MI_PER_KM))} mi` : `${fmtNum(Math.round(km))} km`;

export function fmtDuration(min: number) {
  const h = Math.floor(min / 60);
  const m = Math.round(min % 60);
  return h ? `${h} h ${String(m).padStart(2, '0')}` : `${m} min`;
}

let savedNow: string[] = (() => {
  try { return JSON.parse(read('nxg-saved') ?? '[]').filter((x: unknown) => typeof x === 'string'); } catch { return []; }
})();
export const getSaved = () => savedNow.slice();
export const isSaved = (id: string) => savedNow.includes(id);
export function toggleSaved(id: string) {
  savedNow = isSaved(id) ? savedNow.filter((x) => x !== id) : [...savedNow, id];
  write('nxg-saved', JSON.stringify(savedNow));
  document.dispatchEvent(new CustomEvent('nxg:saved', { detail: { id, saved: isSaved(id) } }));
  return isSaved(id);
}

let toastTimer: number | undefined;
export function toast(message: string) {
  const el = document.querySelector<HTMLElement>('[data-toast]');
  const text = el?.querySelector('span');
  if (!el || !text) return;
  text.textContent = message;
  el.classList.add('is-on');
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => el.classList.remove('is-on'), 2400);
}

export const reducedMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

// Interface text for the page's language, written into the page by SiteUi.
import type { ClientStrings } from './i18n';
let stringsCache: ClientStrings | null = null;
export function T(): ClientStrings {
  if (!stringsCache) {
    try { stringsCache = JSON.parse(document.getElementById('nxg-i18n')?.textContent ?? '{}'); } catch { stringsCache = null; }
  }
  return stringsCache as ClientStrings;
}
export const fill = (s: string, vars: Record<string, string | number> = {}) =>
  s.replace(/\{(\w+)\}/g, (_, k) => (k in vars ? String(vars[k]) : `{${k}}`));

export interface IndexEntry {
  id: string; t: string; p: string; k: string; c: string; d: string; x: string;
  min: number; url: string; thumb: string; img: string; alt: string;
}
let indexCache: IndexEntry[] | null = null;
export function guideIndex(): IndexEntry[] {
  if (!indexCache) {
    try { indexCache = JSON.parse(document.getElementById('nxg-index')?.textContent ?? '[]'); } catch { indexCache = []; }
  }
  return indexCache ?? [];
}

export const matchesQuery = (g: IndexEntry, q: string) =>
  !q || `${g.t} ${g.c} ${g.x} ${g.d} ${g.p}`.toLowerCase().includes(q.trim().toLowerCase());

/** Render a number element: [data-km] follows the units setting; [data-count] can be part-way through counting up. */
export function renderNumber(el: HTMLElement, progress = 1) {
  const prefix = el.dataset.prefix ?? '';
  if (el.dataset.km !== undefined) {
    const km = Number(el.dataset.km) * progress;
    el.textContent = prefix + fmtKm(km);
    return;
  }
  const to = Number(el.dataset.to ?? 0) * progress;
  const neg = el.dataset.neg === '1' && to !== 0 ? '−' : '';
  el.textContent = prefix + neg + fmtNum(to, Number(el.dataset.dec ?? 0)) + (el.dataset.suffix ?? '');
}

// Festivals: dates come as JSON ({s: start, e: end, t: "6–20 Feb 2027"}, from
// src/lib/events.ts) and are compared with the reader's today, so countdowns
// stay right however long ago the page was built.
export interface EventDay { s: string; e: string; t: string }
export interface NextEvent { d: EventDay; days: number; on: boolean }

export function nextEvent(dates: EventDay[]): NextEvent | null {
  const now = new Date();
  const today = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
  for (const d of [...dates].sort((a, b) => a.s.localeCompare(b.s))) {
    const start = Date.parse(d.s);
    if (Date.parse(d.e) >= today) return { d, days: Math.round((start - today) / 864e5), on: start <= today };
  }
  return null;
}

export function countdown(n: NextEvent | null): string {
  if (!n) return 'Next dates coming soon';
  if (n.on) return 'On now';
  if (n.days === 1) return 'Tomorrow';
  if (n.days < 60) return `In ${n.days} days`;
  return `In ${Math.round(n.days / 30.44)} months`;
}

/** Fill every [data-event] element: [data-event-date] gets the next dates, [data-event-in] the countdown. */
export function hydrateEvents(root: ParentNode = document) {
  const els = [...root.querySelectorAll<HTMLElement>('[data-event]')];
  if (root instanceof HTMLElement && root.matches('[data-event]')) els.unshift(root);
  els.forEach((el) => {
    const n = nextEvent(JSON.parse(el.dataset.event ?? '[]'));
    el.dataset.next = n ? n.d.s : '9999';
    el.querySelectorAll('[data-event-date]').forEach((x) => { if (n) x.textContent = n.d.t; });
    if (n) {
      const start = new Date(`${n.d.s}T00:00:00Z`);
      el.querySelectorAll('[data-event-day]').forEach((x) => (x.textContent = String(start.getUTCDate())));
      el.querySelectorAll('[data-event-mon]').forEach((x) => (x.textContent = start.toLocaleDateString('en-GB', { month: 'short', timeZone: 'UTC' })));
      el.querySelectorAll('[data-event-yr]').forEach((x) => (x.textContent = String(start.getUTCFullYear())));
    }
    el.querySelectorAll('[data-event-in]').forEach((x) => {
      x.textContent = countdown(n);
      x.classList.toggle('is-on', !!n?.on);
    });
  });
}

/** Live "days / hours / minutes" boxes: [data-countdown] inside an element hydrated by hydrateEvents. */
export function startCountdowns(root: ParentNode = document) {
  const boxes = [...root.querySelectorAll<HTMLElement>('[data-countdown]')];
  if (!boxes.length) return;
  const tick = () =>
    boxes.forEach((box) => {
      const host = box.closest<HTMLElement>('[data-next]');
      const next = host?.dataset.next;
      if (!next || next === '9999') return;
      const [y, m, d] = next.split('-').map(Number);
      const ms = new Date(y, m - 1, d).getTime() - Date.now();
      box.classList.toggle('is-on', ms <= 0);
      const left = Math.max(0, ms);
      const set = (k: string, v: number) => { const el = box.querySelector(`[data-cd="${k}"]`); if (el) el.textContent = String(v).padStart(2, '0'); };
      set('d', Math.floor(left / 864e5));
      set('h', Math.floor((left % 864e5) / 36e5));
      set('m', Math.floor((left % 36e5) / 6e4));
    });
  tick();
  window.setInterval(tick, 30_000);
}
