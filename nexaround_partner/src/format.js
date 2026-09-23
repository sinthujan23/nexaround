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

// The partner API accepts only these three; spam is an admin-only status.
export const ENQUIRY_STATUSES = ['new', 'contacted', 'closed'];
export const STATUS_LABELS = { new: 'New', contacted: 'Contacted', closed: 'Closed', spam: 'Spam' };

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

// New needs action (amber), contacted is in progress (blue), closed is done
// (green).
export const STATUS_TONES = { new: 'amber', contacted: 'blue', closed: 'green', spam: 'rose' };

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
