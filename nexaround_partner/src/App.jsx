import { useCallback, useEffect, useEffectEvent, useState } from 'react';
import { apiPost, apiGet } from './api';
import {
  CompassIcon, TicketIcon, InboxIcon, MapPinIcon, LogOutIcon, BellIcon,
} from './components/Icons';
import Dashboard from './pages/Dashboard';
import Packages from './pages/Packages';
import Enquiries from './pages/Enquiries';
import Profile from './pages/Profile';
import SetPassword from './pages/SetPassword';
import ForgotPassword from './pages/ForgotPassword';
import ErrorBoundary from './components/ErrorBoundary';
import LiveAlerts from './components/LiveAlerts';
import NotificationBell from './components/NotificationBell';
import { AuthLayout } from './components/Kit';
import {
  RESYNC, broadcastLive, connectLiveStream, desktopAlertsPermission, showDesktopAlert,
} from './live';

const BASE_TITLE = document.title;

/**
 * The partner portal shell.
 *
 * Same hand-rolled routing as the admin panel — one page-name in state, no
 * react-router — with one addition it needs and the admin does not: two pages
 * that must render *before* the token gate. The invite link is the first URL
 * any vendor ever opens, and they have no token when they open it.
 */
export default function App() {
  const path = window.location.pathname;
  const [token, setToken] = useState(localStorage.getItem('partner_token'));
  const [me, setMe] = useState(null);
  const [newCount, setNewCount] = useState(0);
  // Bumped by live events, to re-read the new-enquiry count.
  const [statsVersion, setStatsVersion] = useState(0);
  const [alerts, setAlerts] = useState([]);
  const [alertPermission, setAlertPermission] = useState(desktopAlertsPermission);
  const [activePage, setActivePage] = useState('dashboard');
  // An optional target on the page, e.g. the enquiry the dashboard linked to.
  const [pageTarget, setPageTarget] = useState(null);
  const navigate = (page, target = null) => {
    setActivePage(page);
    setPageTarget(target);
  };

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const handleUnauthorized = (e) => {
      localStorage.removeItem('partner_token');
      setToken(null);
      setMe(null);
      setAlerts([]);
      setError(e.detail?.message || 'Session expired. Please sign in again.');
      setActivePage('dashboard');
    };
    window.addEventListener('auth:unauthorized', handleUnauthorized);
    return () => window.removeEventListener('auth:unauthorized', handleUnauthorized);
  }, []);

  // Who is signed in, for the sidebar and the suspension banner. A failure
  // here is already handled: apiGet fires auth:unauthorized on a 401.
  useEffect(() => {
    if (!token) return;
    apiGet('/partner/me').then(setMe).catch(() => {});
  }, [token]);

  // The new-enquiry count on the Enquiries menu item. Re-read on every page
  // change, so replying to an enquiry clears it by the time you look back,
  // and on every live enquiry event, so it moves without a click at all.
  useEffect(() => {
    if (!token) return;
    apiGet('/partner/stats').then((s) => setNewCount(s.enquiries_new || 0)).catch(() => {});
  }, [token, activePage, statsVersion]);

  // Visible from other tabs: "(2) nexARound Partner".
  useEffect(() => {
    document.title = token && newCount > 0 ? `(${newCount}) ${BASE_TITLE}` : BASE_TITLE;
  }, [token, newCount]);

  const dismissAlert = useCallback((id) => {
    setAlerts((list) => list.filter((a) => a.id !== id));
  }, []);

  const openEnquiry = (id) => {
    dismissAlert(id);
    navigate('enquiries', id);
  };

  const onLiveEvent = useEffectEvent((type, data) => {
    broadcastLive(type, data);
    if (type === 'ready' || type === RESYNC || type.startsWith('enquiry.')) {
      setStatsVersion((v) => v + 1);
    }
    if (type === 'account.changed' || type === RESYNC) {
      apiGet('/partner/me').then(setMe).catch(() => {});
    }
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

  // Before the gate, deliberately.
  if (path.startsWith('/set-password')) return <SetPassword />;
  if (path.startsWith('/forgot-password')) return <ForgotPassword />;

  const handleLogin = async (e) => {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      const res = await apiPost('/partner/auth/login', { email, password });
      localStorage.setItem('partner_token', res.access_token);
      setToken(res.access_token);
      setMe(res.me);
      setPassword('');
    } catch (err) {
      setError(err.message || 'Could not sign in.');
    } finally {
      setBusy(false);
    }
  };

  const handleLogout = () => {
    // Tell the server so the token is blacklisted, but do not wait on it — the
    // traveller should be signed out of this browser either way.
    apiPost('/partner/auth/logout', {}).catch(() => {});
    localStorage.removeItem('partner_token');
    setToken(null);
    setMe(null);
    setAlerts([]);
    setActivePage('dashboard');
  };

  if (!token) {
    return (
      <AuthLayout title="Sign in">
        {error && <div className="login-error">{error}</div>}
        <form onSubmit={handleLogin}>
          <div className="form-group">
            <label className="form-label">Email</label>
            <input
              type="email" required className="form-input" autoComplete="username"
              value={email} onChange={(e) => setEmail(e.target.value)}
            />
          </div>
          <div className="form-group">
            <label className="form-label">Password</label>
            <input
              type="password" required className="form-input" autoComplete="current-password"
              value={password} onChange={(e) => setPassword(e.target.value)}
            />
          </div>
          <button type="submit" className="btn btn-primary btn-block" disabled={busy}>
            {busy ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
        <div className="auth-link">
          <a href="/forgot-password">Forgotten your password?</a>
        </div>
      </AuthLayout>
    );
  }

  const NAV = [
    { key: 'dashboard', label: 'Dashboard', Icon: CompassIcon },
    { key: 'packages', label: 'My Packages', Icon: TicketIcon },
    { key: 'enquiries', label: 'Enquiries', Icon: InboxIcon },
    { key: 'profile', label: 'Business Profile', Icon: MapPinIcon },
  ];

  const TITLES = {
    dashboard: 'Dashboard',
    packages: 'My Packages',
    enquiries: 'Enquiries',
    profile: 'Business Profile',
  };

  const renderContent = () => {
    switch (activePage) {
      case 'packages': return <Packages key={pageTarget || 'all'} initialTarget={pageTarget} />;
      case 'enquiries':
        return <Enquiries key={pageTarget || 'all'} initialId={pageTarget} vendorName={me?.vendor_name} />;
      case 'profile': return <Profile onSaved={setMe} />;
      default: return <Dashboard onNavigate={navigate} me={me} />;
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
          <NotificationBell loginId={me?.login_id} onNavigate={navigate} />
        </div>

        <nav className="sidebar-nav">
          <div className="nav-section-label">Main Menu</div>
          {NAV.map(({ key, label, Icon }) => (
            <button
              key={key}
              type="button"
              className={`nav-item ${activePage === key ? 'active' : ''}`}
              aria-current={activePage === key ? 'page' : undefined}
              onClick={() => navigate(key)}
            >
              <span className="icon"><Icon size={18} /></span>
              {label}
              {key === 'enquiries' && newCount > 0 && <span className="nav-badge">{newCount}</span>}
            </button>
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
          <button className="logout-btn" title="Sign out" onClick={handleLogout}>
            <LogOutIcon size={16} />
          </button>
        </div>
      </aside>

      <main className="main-content">
        {/* The dashboard's greeting is its title. */}
        {activePage !== 'dashboard' && (
          <div className="page-header">
            <h1 className="page-title">{TITLES[activePage]}</h1>
          </div>
        )}
        <div className={`page-body ${activePage === 'dashboard' ? 'dash' : ''}`}>
          {/* A suspended vendor can still sign in and see why. Every write is
              refused server-side with a 403 regardless of this banner. */}
          {me && me.vendor_is_active === false && (
            <div className="login-error" style={{ marginBottom: '16px' }}>
              Your listing is currently hidden from travellers. Contact NexAround.
            </div>
          )}
          <ErrorBoundary>
            {renderContent()}
          </ErrorBoundary>
        </div>
      </main>

      <LiveAlerts alerts={alerts} onOpen={openEnquiry} onDismiss={dismissAlert} />
    </div>
  );
}
