import { useEffect, useRef } from 'react';
import { useBlocker } from 'react-router-dom';
import { useConfirm } from './confirm';

/**
 * Stops a vendor losing typed work. While `dirty`, leaving the page — a
 * sidebar click, the Back button, closing the tab — asks first.
 *
 * `allow(nextLocation)` returns true for moves that are not "leaving", such as
 * switching tabs inside the same form. Call `guard.release()` just before a
 * deliberate navigation (after a successful save) so it is not blocked by the
 * state that has not re-rendered yet.
 */
export function useUnsavedGuard(dirty, { allow, message } = {}) {
  const confirm = useConfirm();
  const released = useRef(false);

  const blocker = useBlocker(({ nextLocation }) => (
    dirty && !released.current && !(allow && allow(nextLocation))
  ));

  useEffect(() => {
    if (blocker.state !== 'blocked') return;
    confirm({
      title: 'Leave without saving?',
      message: message || 'You have changes that have not been saved. They will be lost.',
      confirmLabel: 'Leave',
      cancelLabel: 'Keep editing',
      danger: true,
    }).then((leave) => (leave ? blocker.proceed() : blocker.reset()));
  }, [blocker, confirm, message]);

  useEffect(() => {
    if (!dirty) return undefined;
    const onBeforeUnload = (e) => { e.preventDefault(); };
    window.addEventListener('beforeunload', onBeforeUnload);
    return () => window.removeEventListener('beforeunload', onBeforeUnload);
  }, [dirty]);

  return {
    release: () => { released.current = true; },
  };
}
