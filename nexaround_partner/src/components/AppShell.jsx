import { useCallback, useEffect, useEffectEvent, useState } from 'react';
import { Link, NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom';
import { apiGet } from '../api';
import { useAuth } from '../auth';
import { NAV_ITEMS, headerFor } from '../routes';
import { BellIcon, LogOutIcon } from './Icons';
import ErrorBoundary from './ErrorBoundary';
import LiveAlerts from './LiveAlerts';
import NotificationBell from './NotificationBell';
import {
  RESYNC, broadcastLive, connectLiveStream, desktopAlertsPermission, showDesktopAlert,
} from '../live';

const BASE_TITLE = document.title;

/**
 * The frame around every signed-in page: sidebar, header, alerts.
 *
 * The live-updates stream is opened here, not in a page, so it survives moving
 * between pages: a page that opened it would drop and reconnect on every click.
 */
export default function AppShell() {
  const { token, me, refreshMe, logout } = useAuth();
  const location = useLocation();
  const navigate = useNavigate();

  const [newCount, setNewCount] = useState(0);
  // Bumped by live events, to re-read the new-enquiry count.
  const [statsVersion, setStatsVersion] = useState(0);
  const [alerts, setAlerts] = useState([]);
  const [alertPermission, setAlertPermission] = useState(desktopAlertsPermission);

  const header = headerFor(location.pathname);
  const badges = { enquiries: newCount };

  // The new-enquiry count on the Enquiries menu item. Re-read on every page
  // change, so replying to an enquiry clears it by the time you look back,
  // and on every live enquiry event, so it moves without a click at all.
  useEffect(() => {
    apiGet('/partner/stats').then((s) => setNewCount(s.enquiries_new || 0)).catch(() => {});
  }, [location.pathname, statsVersion]);

  // Visible from other tabs: "(2) nexARound Partner".
  useEffect(() => {
    document.title = newCount > 0 ? `(${newCount}) ${BASE_TITLE}` : BASE_TITLE;
    return () => { document.title = BASE_TITLE; };
  }, [newCount]);

  const dismissAlert = useCallback((id) => {
    setAlerts((list) => list.filter((a) => a.id !== id));
  }, []);

  const openEnquiry = (id) => {
    dismissAlert(id);
    navigate(`/enquiries/${id}`);
  };

  const onLiveEvent = useEffectEvent((type, data) => {
    broadcastLive(type, data);
    if (type === 'ready' || type === RESYNC || type.startsWith('enquiry.')) {
      setStatsVersion((v) => v + 1);
    }
    if (type === 'account.changed' || type === RESYNC) refreshMe();
    if (type === 'enquiry.created') {
      // Newest on top, at most three: a burst should not bury the page.
      setAlerts((list) => [data, ...list.filter((a) => a.id !== data.id)].slice(0, 3));
      if (document.visibilityState !== 'visible') {
        showDesktopAlert({
          title: `New enquiry from ${data.contact_name}`,
          body: data.package_title || 'General enquiry',
          tag: `enquiry-${data.id}`,
          onClick: () => openEnquiry(data.id),
        });
      }
    }
  });

  // One live-updates stream per signed-in tab. Signing out, or the stream
  // saying the session is over, closes it.
  useEffect(() => {
    if (!token) return undefined;
    return connectLiveStream({
      onEvent: (type, data) => onLiveEvent(type, data),
      onSessionEnded: (message) => {
        window.dispatchEvent(new CustomEvent('auth:unauthorized', { detail: { message } }));
      },
    });
  }, [token]);

  const enableDesktopAlerts = async () => {
    try {
      setAlertPermission(await Notification.requestPermission());
    } catch {
      setAlertPermission(desktopAlertsPermission());
    }
  };

  return (
    <div className="admin-layout">
      <aside className="sidebar">
        <div className="sidebar-logo">
          <span className="logo-tile">
            <img src="/logo_2.png" alt="nexARound" onError={(e) => { e.currentTarget.style.display = 'none'; }} />
          </span>
          <div>
            <div className="brand">nexARound</div>
            <div className="brand-sub">PARTNER PORTAL</div>
          </div>
          <NotificationBell loginId={me?.login_id} />
        </div>

        <nav className="sidebar-nav">
          <div className="nav-section-label">Main Menu</div>
          {NAV_ITEMS.map(({ to, label, Icon, badge }) => (
            // Not `end`: /packages/new still lights up My Packages.
            <NavLink key={to} to={to} className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}>
              <span className="icon"><Icon size={18} /></span>
              {label}
              {badge && badges[badge] > 0 && <span className="nav-badge">{badges[badge]}</span>}
            </NavLink>
          ))}
        </nav>

        {alertPermission === 'default' && (
          <button type="button" className="alerts-optin" onClick={enableDesktopAlerts}>
            <span className="alerts-optin-icon"><BellIcon size={16} /></span>
            <span>
              <strong>Turn on desktop alerts</strong>
              <small>Hear about new enquiries while you work in other tabs.</small>
            </span>
          </button>
        )}

        <div className="sidebar-footer">
          <div className="admin-user">
            <div className="admin-avatar">
              {(me?.vendor_name || '?').charAt(0).toUpperCase()}
            </div>
            <div className="user-info" style={{ display: 'flex', flexDirection: 'column', minWidth: 0, flex: 1, gap: '2px' }}>
              <div className="admin-name" title={me?.vendor_name || ''}>{me?.vendor_name || 'Loading…'}</div>
              <div className="admin-role" title={me?.email || ''}>{me?.email || ''}</div>
            </div>
          </div>
          <button className="logout-btn" title="Sign out" onClick={logout}>
            <LogOutIcon size={16} />
          </button>
        </div>
      </aside>

      <main className="main-content">
        {header?.title && (
          <div className="page-header">
            <div>
              {header.back && <Link to={header.back.to} className="page-back">← {header.back.label}</Link>}
              <h1 className="page-title">{header.title}</h1>
            </div>
          </div>
        )}
        <div className={`page-body ${header && !header.title ? 'dash' : ''}`}>
          {/* A suspended vendor can still sign in and see why. Every write is
              refused server-side with a 403 regardless of this banner. */}
          {me && me.vendor_is_active === false && (
            <div className="login-error" style={{ marginBottom: '16px' }}>
              Your listing is currently hidden from travellers. Contact NexAround.
            </div>
          )}
          <ErrorBoundary resetKey={location.pathname}>
            <Outlet />
          </ErrorBoundary>
        </div>
      </main>

      <LiveAlerts alerts={alerts} onOpen={openEnquiry} onDismiss={dismissAlert} />
    </div>
  );
}
