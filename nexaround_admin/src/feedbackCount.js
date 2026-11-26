import { useEffect, useState } from 'react';
import { apiGet } from './api';

// Fired after the Feedback page changes something (an item opened, a status
// set, a reply sent), so the sidebar badge follows at once.
const CHANGED = 'feedback-changed';

export const notifyFeedbackChanged = () => window.dispatchEvent(new Event(CHANGED));

/** New feedback items (messages and "Not great" ratings), refreshed every
 * minute. Off (null) for a team member without the Feedback area. */
export function useFeedbackNew(enabled = true) {
  const [count, setCount] = useState(null);
  useEffect(() => {
    if (!enabled) return undefined;
    let active = true;
    const load = () => apiGet('/admin/feedback/counts')
      .then((c) => { if (active) setCount(c.new); })
      .catch(() => {});
    load();
    const timer = setInterval(load, 60000);
    window.addEventListener(CHANGED, load);
    return () => {
      active = false;
      clearInterval(timer);
      window.removeEventListener(CHANGED, load);
    };
  }, [enabled]);
  return count;
}
