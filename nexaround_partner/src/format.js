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

// Every status a request can be in, for the inbox filters. The server's
// enquiry_lifecycle.py owns the rules; spam is an admin-only status.
export const ENQUIRY_STATUSES = [
  'new', 'contacted', 'confirmed', 'closed', 'customer_cancelled', 'provider_cancelled',
];
// What a vendor may set. Only the traveller can record their own cancellation.
export const VENDOR_STATUSES = ['new', 'contacted', 'confirmed', 'closed', 'provider_cancelled'];
export const CANCELLED_STATUSES = ['customer_cancelled', 'provider_cancelled'];
export const STATUS_LABELS = {
  new: 'New',
  contacted: 'Contacted',
  confirmed: 'Confirmed',
  closed: 'Closed',
  customer_cancelled: 'Cancelled by traveller',
  provider_cancelled: 'Cancelled by you',
  spam: 'Spam',
};

// The last day a confirmed booking can be cancelled for free: 72 hours before
// the start of the booked day ("2026-10-20" -> "2026-10-17"). The server sends
// the same as free_cancellation_last_day; this is for the confirm form, before
// there is one.
export const freeCancellationLastDay = (isoDate) => {
  if (!isoDate) return null;
  const d = new Date(`${isoDate}T00:00:00`);
  d.setDate(d.getDate() - 3);
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};

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

// New needs action (amber), contacted is in progress (blue), confirmed is a
// booking (teal), closed is done (green), and either cancellation is rose.
export const STATUS_TONES = {
  new: 'amber',
  contacted: 'blue',
  confirmed: 'teal',
  closed: 'green',
  customer_cancelled: 'rose',
  provider_cancelled: 'rose',
  spam: 'rose',
};

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

export const formatPrice = (pkg) =>
  pkg.price_amount != null
    ? `${pkg.price_currency || 'LKR'} ${Number(pkg.price_amount).toLocaleString()}`
    : 'On request';

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

// preferred_date is a plain YYYY-MM-DD; parse it as a calendar date, not UTC midnight.
export const formatDay = (value) => {
  if (!value) return null;
  const [y, m, d] = value.split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString('en-GB', {
    weekday: 'short', day: 'numeric', month: 'short', year: 'numeric',
  });
};

export const guestsLabel = (n) => (n ? `${n} ${n === 1 ? 'guest' : 'guests'}` : null);

// Digits only: wa.me rejects spaces, dashes and a leading +.
export const digitsOnly = (phone) => (phone || '').replace(/\D/g, '');
