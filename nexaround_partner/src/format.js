// Labels and formatters shared by the partner pages.

export const CATEGORIES = [
  { value: 'boat', label: 'Boat ride' },
  { value: 'water_sports', label: 'Water sports' },
  { value: 'guided_tour', label: 'Guided tour' },
  { value: 'wildlife', label: 'Wildlife' },
  { value: 'cultural', label: 'Cultural' },
  { value: 'adventure', label: 'Adventure' },
  { value: 'food', label: 'Food' },
  { value: 'other', label: 'Other' },
];

export const PRICE_BASES = [
  { value: 'per_person', label: 'Per person' },
  { value: 'per_group', label: 'Per group' },
  { value: 'from', label: 'Starting from' },
  { value: 'on_request', label: 'On request' },
];

// How far ahead travellers may pick a date. '' is the platform default, which
// the server and the app both treat as a year.
export const BOOKING_WINDOWS = [
  { value: '', label: 'Up to a year (default)' },
  { value: 7, label: '1 week ahead' },
  { value: 14, label: '2 weeks ahead' },
  { value: 30, label: '1 month ahead' },
  { value: 60, label: '2 months ahead' },
  { value: 90, label: '3 months ahead' },
  { value: 180, label: '6 months ahead' },
];

// The presets, plus the package's own value when NexAround set it to something
// else, so opening the package does not lose it.
export const bookingWindowOptions = (current) =>
  current === '' || current == null || BOOKING_WINDOWS.some((w) => w.value === Number(current))
    ? BOOKING_WINDOWS
    : [...BOOKING_WINDOWS, { value: Number(current), label: `${current} days ahead` }];

// Colour families (see the .tone-* classes in index.css). One per category,
// so a boat trip and a food tour read differently at a glance.
const CATEGORY_TONES = {
  boat: 'blue',
  water_sports: 'cyan',
  guided_tour: 'amber',
  wildlife: 'green',
  cultural: 'violet',
  adventure: 'orange',
  food: 'rose',
};

export const categoryTone = (value) => CATEGORY_TONES[value] || 'teal';

// is_published is the server's word, not the form's: it also needs the whole
// listing to be live, which only NexAround can switch.
export const visibility = (pkg) => {
  if (!pkg.is_active) return 'Hidden';
  return pkg.is_published ? 'Live' : 'On, not visible';
};

export const visibilityTone = (pkg) => {
  if (!pkg.is_active) return 'gray';
  return pkg.is_published ? 'green' : 'amber';
};

export const categoryLabel = (value) => CATEGORIES.find((c) => c.value === value)?.label || value || 'Other';
export const basisLabel = (value) => PRICE_BASES.find((b) => b.value === value)?.label || 'Per person';

// The main price, and how many other prices there are.
export const formatPrice = (pkg) => {
  if (pkg.price_amount == null) return 'On request';
  const more = (pkg.price_options?.length || 1) - 1;
  return `${pkg.price_currency || 'LKR'} ${Number(pkg.price_amount).toLocaleString()}`
    + (more > 0 ? ` +${more} more` : '');
};

export const formatDuration = (minutes) => {
  if (!minutes) return null;
  if (minutes < 60) return `${minutes} min`;
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return m ? `${h} h ${m} min` : `${h} h`;
};

const TZ = 'Asia/Colombo';

export const formatDateTime = (value) =>
  value
    ? new Date(value).toLocaleString('en-GB', {
      day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: TZ,
    })
    : '—';

// Short age for lists: "5m", "3h", "2d", then a date.
export const formatAge = (value) => {
  if (!value) return '';
  const minutes = Math.floor((Date.now() - new Date(value).getTime()) / 60000);
  if (minutes < 1) return 'now';
  if (minutes < 60) return `${minutes}m`;
  if (minutes < 60 * 24) return `${Math.floor(minutes / 60)}h`;
  if (minutes < 60 * 24 * 7) return `${Math.floor(minutes / 1440)}d`;
  return new Date(value).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', timeZone: TZ });
};

