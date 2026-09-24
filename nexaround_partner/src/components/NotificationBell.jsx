import { useEffect, useEffectEvent, useRef, useState } from 'react';
import { apiGet, apiPost, useApi } from '../api';
import { RESYNC, useLiveEvent } from '../live';
import { formatAge, formatDateTime } from '../format';
import {
  BellIcon, CrossIcon, InboxIcon, CheckIcon, PlusIcon, EditIcon, EyeOffIcon, TrashIcon, MapPinIcon,
} from './Icons';

/**
 * The bell in the sidebar header: an unread count, and a panel with two tabs.
 * "Notifications" is what other people did — travellers, teammates, NexAround;
 * "Activity" is the whole log, the vendor's own actions included.
 *
 * Unread is per login and server-side (vendor_users.activity_seen_at), so it
 * survives a reload and one teammate reading the feed does not clear it for
 * the others. Opening the panel marks everything seen; lines that were new at
 * that moment stay highlighted until it closes.
 */

const PAGE = 20;

// Icon and .tone-* colour per kind. Amber stays reserved for new enquiries.
const KINDS = {
  'enquiry.created': [InboxIcon, 'amber'],
  'enquiry.status': [CheckIcon, 'blue'],
  'package.created': [PlusIcon, 'cyan'],
  'package.updated': [EditIcon, 'cyan'],
  'package.live': [CheckIcon, 'green'],
  'package.hidden': [EyeOffIcon, 'gray'],
  'package.deleted': [TrashIcon, 'rose'],
  'profile.updated': [MapPinIcon, 'violet'],
  'listing.suspended': [EyeOffIcon, 'rose'],
  'listing.restored': [CheckIcon, 'green'],
};

const actorLabel = (item, loginId) => {
  if (item.actor === 'admin') return 'NexAround';
  if (item.actor === 'vendor') {
    return item.actor_login_id === loginId ? 'You' : (item.actor_name || 'A teammate');
  }
  return null; // a traveller: their name is already the title
};

export default function NotificationBell({ loginId, onNavigate }) {
  const [unread, setUnread] = useState(0);
  const [open, setOpen] = useState(false);
  const [countVersion, setCountVersion] = useState(0);
  const wrapRef = useRef(null);

  useEffect(() => {
    let active = true;
    apiGet('/partner/activity/unread')
      .then((r) => { if (active) setUnread(r.unread || 0); })
      .catch(() => {});
    return () => { active = false; };
  }, [countVersion]);

  const markSeen = () => {
    apiPost('/partner/activity/seen', {}).then(() => setUnread(0)).catch(() => {});
  };

  useLiveEvent(['activity.created', 'activity.seen', RESYNC], ({ type, data }) => {
    if (type === RESYNC) {
      setCountVersion((v) => v + 1);
    } else if (type === 'activity.seen') {
      // This login read the feed in another tab.
      if (data.login_id === loginId) setUnread(0);
    } else if (data.actor_login_id !== loginId || !loginId) {
      // Already looking at it: it lands in the open panel, so it is seen.
      if (open) markSeen();
      else setUnread((n) => n + 1);
    }
  });

  // Close on a click outside or Escape.
  useEffect(() => {
    if (!open) return undefined;
    const onDown = (e) => { if (!wrapRef.current?.contains(e.target)) setOpen(false); };
    const onKey = (e) => { if (e.key === 'Escape') setOpen(false); };
    document.addEventListener('mousedown', onDown);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('mousedown', onDown);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  const pick = (item) => {
    setOpen(false);
    if (item.enquiry_id) onNavigate('enquiries', item.enquiry_id);
    else if (item.package_id) onNavigate('packages', item.package_id);
    else if (item.kind.startsWith('package.')) onNavigate('packages');
    else onNavigate('profile');
  };

  return (
    <div className="bell-wrap" ref={wrapRef}>
      <button
        type="button"
        className={`bell-btn ${open ? 'open' : ''}`}
        aria-label={unread ? `Notifications, ${unread} unread` : 'Notifications'}
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
      >
        <BellIcon size={18} />
        {unread > 0 && <span className="bell-badge">{unread > 9 ? '9+' : unread}</span>}
      </button>
      {open && (
        <NotificationPanel
          loginId={loginId}
          onClose={() => setOpen(false)}
          onSeen={() => setUnread(0)}
          onPick={pick}
        />
      )}
    </div>
  );
}

function NotificationPanel({ loginId, onClose, onSeen, onPick }) {
  const [tab, setTab] = useState('notifications');
  // This login's watermark from before the panel opened: lines newer than it
  // are highlighted. Read first, then moved to now.
  const [seenAt, setSeenAt] = useState(null);
  const markedSeen = useEffectEvent(onSeen);

  useEffect(() => {
    let active = true;
    apiGet('/partner/activity/unread')
      .then((r) => {
        if (!active) return null;
        setSeenAt(r.seen_at || '');
        return apiPost('/partner/activity/seen', {}).then(() => markedSeen());
      })
      .catch(() => {});
    return () => { active = false; };
  }, []);

  return (
    <div className="notif-panel" role="dialog" aria-label="Notifications">
      <div className="notif-head">
        <div className="notif-heading">Notifications</div>
        <button type="button" className="notif-close" aria-label="Close" onClick={onClose}>
          <CrossIcon size={14} />
        </button>
      </div>
      <div className="notif-tabs" role="tablist">
        {[['notifications', 'For you'], ['all', 'All activity']].map(([key, label]) => (
          <button
            key={key}
            type="button"
            role="tab"
            aria-selected={tab === key}
            className={`notif-tab ${tab === key ? 'active' : ''}`}
            onClick={() => setTab(key)}
          >
            {label}
          </button>
        ))}
      </div>
      <FeedList key={tab} scope={tab} loginId={loginId} seenAt={seenAt} onPick={onPick} />
    </div>
  );
}

function FeedList({ scope, loginId, seenAt, onPick }) {
  const { data, error } = useApi(`/partner/activity?scope=${scope}&limit=${PAGE}`);
  const [live, setLive] = useState([]);
  const [older, setOlder] = useState([]);
  const [olderHasMore, setOlderHasMore] = useState(null);
  const [busy, setBusy] = useState(false);

  // Lines that arrive while the panel is open go on top.
  useLiveEvent('activity.created', ({ data: item }) => {
    if (scope === 'notifications' && loginId && item.actor_login_id === loginId) return;
    setLive((list) => [item, ...list]);
  });

  // A live line can also be in the first page if it landed mid-fetch.
  const ids = new Set();
  const items = [...live, ...(data?.items || []), ...older].filter((i) => {
    if (ids.has(i.id)) return false;
    ids.add(i.id);
    return true;
  });
  const hasMore = olderHasMore ?? data?.has_more ?? false;
  const since = seenAt ? new Date(seenAt).getTime() : null;

  const loadOlder = async () => {
    const last = items[items.length - 1];
    if (!last) return;
    setBusy(true);
    try {
      const res = await apiGet(
        `/partner/activity?scope=${scope}&limit=${PAGE}&before=${encodeURIComponent(last.created_at)}`
      );
      setOlder((list) => [...list, ...res.items]);
      setOlderHasMore(res.has_more);
    } catch {
      // The button stays; the vendor can try again.
    } finally {
      setBusy(false);
    }
  };

  if (error) return <div className="notif-empty">Could not load notifications.</div>;
  if (!data) return <div className="notif-empty"><div className="loader" /></div>;
  if (!items.length) {
    return (
      <div className="notif-empty">
        <BellIcon size={28} />
        <strong>{scope === 'notifications' ? 'You’re all caught up' : 'No activity yet'}</strong>
        {scope === 'notifications'
          ? 'New enquiries and changes made by your team or NexAround appear here.'
          : 'Everything that happens to your listing is logged here.'}
      </div>
    );
  }

  return (
    <div className="notif-list">
      {items.map((item) => {
        const [Icon, tone] = KINDS[item.kind] || [BellIcon, 'gray'];
        const actor = actorLabel(item, loginId);
        const mine = loginId && item.actor_login_id === loginId;
        const fresh = !mine && since !== null && new Date(item.created_at).getTime() > since;
        return (
          <button
            key={item.id}
            type="button"
            className={`notif-row ${fresh ? 'fresh' : ''}`}
            onClick={() => onPick(item)}
          >
            <span className={`notif-icon tone-${tone}`}><Icon size={15} /></span>
            <span className="notif-main">
              <span className="notif-title">{item.title}</span>
              {item.body && <span className="notif-body">{item.body}</span>}
              <span className="notif-meta" title={formatDateTime(item.created_at)}>
                {formatAge(item.created_at)}{actor && ` · by ${actor}`}
              </span>
            </span>
            {fresh && <span className="notif-dot" aria-label="New" />}
          </button>
        );
      })}
      {hasMore && (
        <button type="button" className="notif-more" disabled={busy} onClick={loadOlder}>
          {busy ? 'Loading…' : 'Show older'}
        </button>
      )}
    </div>
  );
}
