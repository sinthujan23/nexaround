import { useEffect, useEffectEvent } from 'react';
import { Link, NavLink, Outlet, useLocation } from 'react-router-dom';
import { useAuth } from '../auth';
import { NAV_ITEMS, headerFor } from '../routes';
import { LogOutIcon } from './Icons';
import ErrorBoundary from './ErrorBoundary';
import NotificationBell from './NotificationBell';
import { RESYNC, broadcastLive, connectLiveStream } from '../live';

/**
 * The frame around every signed-in page: sidebar and header. No enquiry
 * alerts: travellers' requests go to NexAround, not the vendor.
 *
 * The live-updates stream is opened here, not in a page, so it survives moving
 * between pages: a page that opened it would drop and reconnect on every click.
 */
export default function AppShell() {
  const { token, me, refreshMe, logout } = useAuth();
  const location = useLocation();

  const header = headerFor(location.pathname);

  const onLiveEvent = useEffectEvent((type, data) => {
    broadcastLive(type, data);
    if (type === 'account.changed' || type === RESYNC) refreshMe();
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
          {NAV_ITEMS.map(({ to, label, Icon }) => (
            // Not `end`: /packages/new still lights up My Packages.
            <NavLink key={to} to={to} className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}>
              <span className="icon"><Icon size={18} /></span>
              {label}
            </NavLink>
          ))}
        </nav>

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
    </div>
  );
}
