// Museums: what the admin pages share. The rules mirror the server's
// (museums_admin, MuseumRepository.get_itinerary) and the app's guide page.

// The tours a museum guide offers, in the app's order and wording.
export const DURATIONS = ['3h', '5h', '1d', '2d'];
export const TOUR_LABELS = { '3h': '3 Hours', '5h': '5 Hours', '1d': '1 Day', '2d': '2 Days' };

/** "3.8M visitors/yr", as the app's list card shows it; '' when unknown. */
export const formatVisitors = (n) => (n ? `${(n / 1e6).toFixed(1)}M visitors/yr` : '');

/**
 * The items of one tour in walking order, as the app shows them: by the
 * tour's own stop number, then by the item's place in the full list.
 */
export function tourOrder(items, d) {
  return items
    .map((item, index) => ({ item, rank: index + 1 }))
    .filter(({ item }) => item[`included_${d}`])
    .sort((a, b) => ((a.item[`stop_${d}`] ?? a.rank) - (b.item[`stop_${d}`] ?? b.rank)) || (a.rank - b.rank))
    .map(({ item }) => item);
}

/** Every tour's stops set to 1..n in its current order, others cleared. */
export function renumberTours(items) {
  const stops = Object.fromEntries(DURATIONS.map((d) => [
    d, new Map(tourOrder(items, d).map((item, i) => [item.key, i + 1])),
  ]));
  return items.map((item) => ({
    ...item,
    ...Object.fromEntries(DURATIONS.map((d) => [`stop_${d}`, stops[d].get(item.key) ?? null])),
  }));
}

// The app's category colours and icons (museum_guide_page.dart), so the
// preview looks like the phone. First match wins, as there.
const CATEGORY_STYLES = [
  [['imperial'], '#DAA520'],
  [['renaissance'], '#1565C0'],
  [['sculpture'], '#6D4C41'],
  [['antiquit'], '#BF360C'],
  [['dutch', 'flemish'], '#E65100'],
  [['impressioni'], '#7B1FA2'],
  [['modern', 'cubism'], '#00897B'],
  [['baroque'], '#880E4F'],
  [['decorative'], '#00838F'],
  [['french'], '#283593'],
  [['spanish'], '#C62828'],
  [['british', 'german'], '#37474F'],
  [['treasury'], '#FF8F00'],
  [['architect'], '#558B2F'],
  [['arms'], '#455A64'],
];
const ICON_ORDER = ['imperial', 'sculpture', 'antiquit', 'decorative', 'arms', 'treasury', 'architect'];
const ICONS = {
  imperial: 'castle', sculpture: 'accessibility_new', antiquit: 'temple_hindu', decorative: 'diamond',
  arms: 'shield', treasury: 'lock', architect: 'architecture',
};

export function categoryColor(category) {
  const lower = (category || '').toLowerCase();
  const hit = CATEGORY_STYLES.find(([words]) => words.some((w) => lower.includes(w)));
  return hit ? hit[1] : '#007A7C';
}

export function categoryIcon(category) {
  const lower = (category || '').toLowerCase();
  const word = ICON_ORDER.find((w) => lower.includes(w));
  return word ? ICONS[word] : 'palette';
}
