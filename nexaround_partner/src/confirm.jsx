import { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react';

const ConfirmContext = createContext(null);

/**
 * `await confirm({ title, message, confirmLabel, danger })` resolves true or
 * false. Replaces the browser's `window.confirm`, which looks like a phishing
 * pop-up and cannot be styled or described.
 */
export function ConfirmProvider({ children }) {
  const [dialog, setDialog] = useState(null);
  const resolver = useRef(null);

  const confirm = useCallback((options) => new Promise((resolve) => {
    resolver.current = resolve;
    setDialog(options);
  }), []);

  const close = useCallback((answer) => {
    resolver.current?.(answer);
    resolver.current = null;
    setDialog(null);
  }, []);

  useEffect(() => {
    if (!dialog) return undefined;
    const onKey = (e) => { if (e.key === 'Escape') close(false); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [dialog, close]);

  return (
    <ConfirmContext.Provider value={confirm}>
      {children}
      {dialog && (
        <div className="dialog-overlay" onClick={() => close(false)}>
          <div className="dialog" role="alertdialog" aria-modal="true" aria-label={dialog.title} onClick={(e) => e.stopPropagation()}>
            <div className="dialog-title">{dialog.title}</div>
            {dialog.message && <div className="dialog-message">{dialog.message}</div>}
            <div className="dialog-actions">
              <button type="button" className="btn btn-ghost btn-sm" onClick={() => close(false)}>
                {dialog.cancelLabel || 'Cancel'}
              </button>
              <button
                type="button" autoFocus
                className={`btn btn-sm ${dialog.danger ? 'btn-danger' : 'btn-primary'}`}
                onClick={() => close(true)}
              >
                {dialog.confirmLabel || 'Confirm'}
              </button>
            </div>
          </div>
        </div>
      )}
    </ConfirmContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components
export function useConfirm() {
  const confirm = useContext(ConfirmContext);
  if (!confirm) throw new Error('useConfirm needs a ConfirmProvider');
  return confirm;
}
