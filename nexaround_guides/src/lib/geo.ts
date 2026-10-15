// Build-time helpers for the route explorer and the animated numbers.

type Pt = [number, number];

export function haversineKm(a: Pt, b: Pt): number {
  const R = 6371;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b[0] - a[0]);
  const dLng = toRad(b[1] - a[1]);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a[0])) * Math.cos(toRad(b[0])) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

interface Leg { from: string; to: string; km: number; min: number }
interface Stop { name: string; lat: number; lng: number; kind: string }

const norm = (s: string) => s.toLowerCase().replace(/\(.*?\)/g, '').replace(/[^a-z0-9]+/g, ' ').trim();
// "Mount Barnett Roadhouse" and "Mount Barnett" are the same place;
// "Caiguna Blowhole" and "Caiguna" are not.
const SAME_PLACE_WORDS = new Set(['roadhouse', 'airport', 'junction', 'station', 'village', 'town', 'ferry']);
const sameName = (a: string, b: string) => {
  const [x, y] = [norm(a), norm(b)].sort((p, q) => p.length - q.length);
  if (x === y) return true;
  return y.startsWith(x + ' ') && y.slice(x.length + 1).split(' ').every((w) => SAME_PLACE_WORDS.has(w));
};

/**
 * Split a route line into the guide's legs. A leg ends at the point of the
 * line nearest the stop with the same name as the leg's `to` town; if no stop
 * matches, the split falls where the leg's share of the total distance puts
 * it. Also returns, for each leg, the stops on or near it (within 25 km of
 * the line, and nearer this line than any `otherLines`).
 */
export function splitLegs(points: Pt[], legs: Leg[], stops: Stop[], otherLines: Pt[][] = []) {
  const n = points.length;
  if (!legs.length || n < 2) return null;
  const cum = [0];
  for (let i = 1; i < n; i++) cum.push(cum[i - 1] + haversineKm(points[i - 1], points[i]));
  const lineKm = cum[n - 1];
  const legKm = legs.reduce((s, l) => s + l.km, 0);

  const bounds = [0];
  let run = 0;
  for (let k = 0; k < legs.length; k++) {
    run += legs[k].km;
    const start = bounds[k];
    const stop = stops.find((s) => sameName(s.name, legs[k].to));
    let at = -1;
    if (stop) {
      // Search only as far ahead as this leg could reach, so a loop route
      // does not snap to the same town on the way back.
      const reach = cum[start] + legs[k].km * 1.3 + 30;
      let best = Infinity;
      for (let i = start + 1; i < n && cum[i] <= reach; i++) {
        const d = haversineKm(points[i], [stop.lat, stop.lng]);
        if (d < best) { best = d; at = i; }
      }
      if (best > 40) at = -1;
    }
    if (at < 0) {
      // The last leg ends where the line ends unless a stop says otherwise.
      if (k === legs.length - 1) at = n - 1;
      else at = cum.findIndex((c) => c >= (run / legKm) * lineKm);
    }
    const maxAt = n - 1 - (legs.length - 1 - k);
    bounds.push(Math.min(Math.max(at, start + 1), maxAt));
  }
  const end = bounds[legs.length];
  const nearest = (line: Pt[], p: Pt) => line.reduce((m, q) => Math.min(m, haversineKm(q, p)), Infinity);

  const along: number[][] = legs.map(() => []);
  const where: { stop: number; at: number; leg: number }[] = [];
  stops.forEach((s, si) => {
    let best = Infinity;
    let at = -1;
    for (let i = 0; i <= end; i++) {
      const d = haversineKm(points[i], [s.lat, s.lng]);
      if (d < best) { best = d; at = i; }
    }
    if (best > 25) return;
    if (otherLines.some((l) => l.length && nearest(l, [s.lat, s.lng]) < best - 1)) return;
    // A stop at a leg boundary belongs to the leg that starts there.
    let leg = bounds.findIndex((b, k) => k < legs.length && at >= b && at < bounds[k + 1]);
    if (leg < 0) leg = legs.length - 1;
    // A town that starts or ends the leg is already in its title.
    if (sameName(s.name, legs[leg].from) || sameName(s.name, legs[leg].to)) return;
    where.push({ stop: si, at, leg });
  });
  where.sort((a, b) => a.at - b.at).forEach((w) => along[w.leg].push(w.stop));

  return legs.map((l, k) => ({ ...l, a: bounds[k], b: bounds[k + 1], stops: along[k] }));
}

/**
 * Split a headline number like "About 2,702 km" or "−67.7 °C" into parts the
 * count-up animation can use. Years, ranges and words return null and stay
 * as they are. `km` is set when the value can be shown in miles.
 */
export function parseFact(value: string) {
  const m = value.match(/^(About |Under |Over |Nearly )?([−-])?([\d,]+(?:\.\d+)?)(.*)$/);
  if (!m) return null;
  const [, prefix = '', neg, digits, suffix] = m;
  if (/^[–-]/.test(suffix)) return null;
  const n = parseFloat(digits.replace(/,/g, ''));
  if (/^\d{4}$/.test(digits) && n >= 1800 && n <= 2100) return null;
  const dec = (digits.split('.')[1] ?? '').length;
  return { prefix, neg: !!neg, n, dec, suffix, km: suffix === ' km' ? n : undefined };
}
