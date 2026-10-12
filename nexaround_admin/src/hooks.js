import { useCallback, useEffect, useRef, useState } from 'react';

/**
 * A short message that hides itself. Returns [toast, notify]; render the
 * toast with <Toast toast={toast} /> from components/Kit.
 *   notify('Saved')  ·  notify('Could not save', 'error')
 */
export function useToast(ms = 3000) {
  const [toast, setToast] = useState(null);
  const timer = useRef(null);

  const notify = useCallback((message, tone = 'ok') => {
    setToast({ message, tone });
    clearTimeout(timer.current);
    timer.current = setTimeout(() => setToast(null), ms);
  }, [ms]);

  useEffect(() => () => clearTimeout(timer.current), []);

  return [toast, notify];
}
