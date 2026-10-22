import { useEffect, useState } from 'react';
import { apiGet } from './api';

// Fired after a decision, so the sidebar badge follows at once.
const CHANGED = 'vendor-changes-changed';

export const notifyVendorChangesChanged = () => window.dispatchEvent(new Event(CHANGED));

/** How many vendor edits wait for an admin, refreshed every minute. */
export function useVendorChangeCount() {
  const [count, setCount] = useState(null);
  useEffect(() => {
    let active = true;
    const load = () => apiGet('/admin/experiences/changes/count')
      .then((c) => { if (active) setCount(c.pending); })
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
