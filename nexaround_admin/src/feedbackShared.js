// Shared by the Feedback page's tabs.

const TZ = 'Asia/Colombo';

export const FEATURE_LABELS = {
  ar: 'AR camera', odyssey: 'Odyssey planner', neva: 'NEVA assistant', discover: 'Discover',
  city_guides: 'City Guides', walking_challenge: 'Walking Challenge', trip_split: 'Trip Split',
  travel_stories: 'Travel Stories', experiences: 'Experiences', museums: 'Museums', forum: 'Forum',
};

const dayKey = (d) => d.toLocaleDateString('en-CA', { timeZone: TZ });
const daysAgo = (v) => Math.round((Date.parse(dayKey(new Date())) - Date.parse(dayKey(new Date(v)))) / 86400000);
const clock = (v) => new Date(v).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: TZ });

export const formatWhen = (v) => {
  if (!v) return '';
  const d = daysAgo(v);
  if (d <= 0) return clock(v);
  if (d === 1) return 'Yesterday';
  if (d < 7) return new Date(v).toLocaleDateString('en-GB', { weekday: 'short', timeZone: TZ });
  return new Date(v).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', timeZone: TZ });
};
export const formatDateTime = (v) => (v ? new Date(v).toLocaleString('en-GB', {
  day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: TZ,
}) : '');
export const formatDate = (v) => (v ? new Date(v).toLocaleDateString('en-GB', {
  day: 'numeric', month: 'short', year: 'numeric', timeZone: TZ,
}) : '');

