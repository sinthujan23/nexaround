import { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react';
import { Toast } from './components/Kit';

const ToastContext = createContext(null);

/**
 * One toast for the whole portal. Every page used to carry its own copy of
 * `const [toast, setToast]` plus a `notify()` with a timer; they now call
 * `useToast()` and the message survives a navigation (save, then go back to
 * the list).
 */
export function ToastProvider({ children }) {
  const [toast, setToast] = useState(null);
  const timer = useRef(null);

  const notify = useCallback((message, tone = 'ok') => {
    clearTimeout(timer.current);
    setToast({ message, tone });
    timer.current = setTimeout(() => setToast(null), 3500);
  }, []);

  useEffect(() => () => clearTimeout(timer.current), []);

  return (
    <ToastContext.Provider value={notify}>
      {children}
      <Toast toast={toast} />
    </ToastContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components
export function useToast() {
  const notify = useContext(ToastContext);
  if (!notify) throw new Error('useToast needs a ToastProvider');
  return notify;
}
