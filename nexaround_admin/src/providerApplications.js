import { useEffect, useState } from 'react';
import { apiGet } from './api';

// Fired after a status change, so the sidebar badge follows at once.
const CHANGED = 'provider-applications-changed';

export const notifyProviderApplicationsChanged = () => window.dispatchEvent(new Event(CHANGED));

/** How many "List your experience" applications are new, refreshed every minute. */
export function useProviderApplicationCount() {
  const [count, setCount] = useState(null);
  useEffect(() => {
    let active = true;
    const load = () => apiGet('/admin/experiences/provider-applications?status=new')
      .then((r) => { if (active) setCount(r.new_count); })
      .catch(() => {});
    load();
    const timer = setInterval(load, 60000);
    window.addEventListener(CHANGED, load);
    return () => {
      active = false;
      clearInterval(timer);
      window.removeEventListener(CHANGED, load);
    };
  }, []);
  return count;
}
