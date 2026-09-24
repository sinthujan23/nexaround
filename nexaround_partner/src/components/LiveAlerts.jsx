import { useEffect } from 'react';
import { BellIcon, CrossIcon } from './Icons';
import { formatDay, guestsLabel } from '../format';

// Long enough to read a name and a package title and reach for the button.
const SHOW_MS = 12_000;

/**
 * New-enquiry alerts, stacked in the top-right corner. Amber, like every
 * other "new enquiry" signal in the portal.
 */
export default function LiveAlerts({ alerts, onOpen, onDismiss }) {
  if (!alerts.length) return null;
  return (
    <div className="live-alerts" role="region" aria-label="New enquiries" aria-live="polite">
      {alerts.map((alert) => (
        <LiveAlert key={alert.id} alert={alert} onOpen={onOpen} onDismiss={onDismiss} />
      ))}
    </div>
  );
}

function LiveAlert({ alert, onOpen, onDismiss }) {
  // The clock only runs while the tab is in view: an alert that arrives in a
  // background tab is still there when the vendor comes back to it.
  useEffect(() => {
    let timer = null;
    const sync = () => {
      clearTimeout(timer);
      if (document.visibilityState === 'visible') {
        timer = setTimeout(() => onDismiss(alert.id), SHOW_MS);
      }
    };
    sync();
    document.addEventListener('visibilitychange', sync);
    return () => {
      clearTimeout(timer);
      document.removeEventListener('visibilitychange', sync);
    };
  }, [alert.id, onDismiss]);

  const meta = [guestsLabel(alert.party_size), formatDay(alert.preferred_date)].filter(Boolean).join(' · ');

  return (
    <div className="live-alert">
      <span className="live-alert-icon"><BellIcon size={16} /></span>
      <div className="live-alert-body">
        <div className="live-alert-kicker">New enquiry</div>
        <div className="live-alert-title">{alert.contact_name}</div>
        <div className="live-alert-sub">{alert.package_title || 'General enquiry'}</div>
        {meta && <div className="live-alert-meta">{meta}</div>}
        <button type="button" className="btn btn-primary btn-sm live-alert-open" onClick={() => onOpen(alert.id)}>
          View enquiry
        </button>
      </div>
      <button type="button" className="live-alert-close" aria-label="Dismiss" onClick={() => onDismiss(alert.id)}>
        <CrossIcon size={14} />
      </button>
    </div>
  );
}
