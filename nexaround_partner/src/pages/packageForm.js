// What the package list and the package page share: the blank form and how a
// form becomes the payload the API takes.

export const EMPTY_PACKAGE = {
  title: '', summary: '', description: '', category: 'boat', tags: [],
  photo_urls: [], unavailable_ranges: [], price_amount: '', price_currency: 'LKR',
  price_basis: 'per_person', duration_minutes: '', max_participants: '',
  booking_window_days: '',
  inclusions: [], languages: [], uses_vendor_location: true,
  meeting_point_address: '', is_active: true, latitude: null, longitude: null,
};

const blankToNull = (v) => (v === '' || v == null ? null : Number(v));

// A package that meets at the business has no point of its own; the server
// copies the vendor's.
export const toPayload = (form) => ({
  ...form,
  price_amount: blankToNull(form.price_amount),
  duration_minutes: blankToNull(form.duration_minutes),
  max_participants: blankToNull(form.max_participants),
  booking_window_days: blankToNull(form.booking_window_days),
  latitude: form.uses_vendor_location ? null : Number(form.latitude),
  longitude: form.uses_vendor_location ? null : Number(form.longitude),
});

/** A package from the API, as the form's fields (numbers become strings). */
export const fromPackage = (pkg) => ({
  ...EMPTY_PACKAGE, ...pkg,
  price_amount: pkg.price_amount ?? '',
  duration_minutes: pkg.duration_minutes ?? '',
  max_participants: pkg.max_participants ?? '',
  booking_window_days: pkg.booking_window_days ?? '',
  summary: pkg.summary || '',
  description: pkg.description || '',
  unavailable_ranges: pkg.unavailable_ranges || [],
});

export const linesToArray = (t) => t.split('\n').map((l) => l.trim()).filter(Boolean);
export const arrayToLines = (a) => (a || []).join('\n');
