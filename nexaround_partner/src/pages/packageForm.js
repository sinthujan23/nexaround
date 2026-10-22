// What the package list and the package page share: the blank form and how a
// form becomes the payload the API takes.

import { optionsToRows, rowsToOptions } from '../components/PriceOptionsEditor';

export const EMPTY_PACKAGE = {
  title: '', summary: '', description: '', category: 'boat', tags: [],
  photo_urls: [], unavailable_ranges: [], price_amount: '', price_currency: 'LKR',
  price_basis: 'per_person', price_rows: optionsToRows([]),
  duration_minutes: '', max_participants: '',
  booking_window_days: '',
  inclusions: [], languages: [], is_active: true,
};

const blankToNull = (v) => (v === '' || v == null ? null : Number(v));

// The meeting point is not the vendor's to send: NexAround sets it.
export const toPayload = ({
  price_rows: priceRows, uses_vendor_location: _u, meeting_point_address: _m,
  latitude: _lat, longitude: _lng, ...form
}) => ({
  ...form,
  // The server keeps the dollar prices NexAround set, by option.
  price_options: rowsToOptions(priceRows, false),
  price_amount: blankToNull(form.price_amount),
  duration_minutes: blankToNull(form.duration_minutes),
  max_participants: blankToNull(form.max_participants),
  booking_window_days: blankToNull(form.booking_window_days),
});

/** A package from the API, as the form's fields (numbers become strings). */
export const fromPackage = (pkg) => ({
  ...EMPTY_PACKAGE, ...pkg,
  price_amount: pkg.price_amount ?? '',
  // No price shows no rows ("On request") rather than a blank one.
  price_rows: pkg.price_options?.length ? optionsToRows(pkg.price_options) : [],
  duration_minutes: pkg.duration_minutes ?? '',
  max_participants: pkg.max_participants ?? '',
  booking_window_days: pkg.booking_window_days ?? '',
  summary: pkg.summary || '',
  description: pkg.description || '',
  unavailable_ranges: pkg.unavailable_ranges || [],
});

export const linesToArray = (t) => t.split('\n').map((l) => l.trim()).filter(Boolean);
export const arrayToLines = (a) => (a || []).join('\n');
