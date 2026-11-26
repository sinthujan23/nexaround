import { useEffect, useState } from 'react';
import { apiGet } from './api';

// Fired after the inbox changes here (a mail opened, moved or answered), so
// the sidebar badge follows at once.
const CHANGED = 'support-mail-changed';

export const notifySupportMailChanged = () => window.dispatchEvent(new Event(CHANGED));

/** Unread mails in support@'s Inbox, refreshed every minute. Off (null)
 * for a team member without the Support inbox area. */
export function useSupportUnread(enabled = true) {
  const [count, setCount] = useState(null);
  useEffect(() => {
    if (!enabled) return undefined;
    let active = true;
    const load = () => apiGet('/admin/support-mail/unread')
      .then((c) => { if (active) setCount(c.unread); })
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
