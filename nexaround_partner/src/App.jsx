import { useEffect, useState } from 'react';
import { apiPost, apiGet } from './api';
import {
  CompassIcon, TicketIcon, InboxIcon, MapPinIcon, LogOutIcon,
} from './components/Icons';
import Dashboard from './pages/Dashboard';
import Packages from './pages/Packages';
import Enquiries from './pages/Enquiries';
import Profile from './pages/Profile';
import SetPassword from './pages/SetPassword';
import ForgotPassword from './pages/ForgotPassword';

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
  const [activePage, setActivePage] = useState('dashboard');

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const handleUnauthorized = (e) => {
      localStorage.removeItem('partner_token');
      setToken(null);
      setMe(null);
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
    setActivePage('dashboard');
  };

  if (!token) {
    return (
      <div className="login-page">
        <div className="login-card">
          <div className="login-logo">
            <img 
              src="/logo_2.png" 
              alt="nexARound" 
              className="login-logo-img" 
              onError={(e) => { e.currentTarget.style.display = 'none'; }} 
            />
            <div className="brand">nexARound</div>
            <p>Partner Portal</p>
          </div>
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
            <button type="submit" className="btn btn-primary" style={{ width: '100%' }} disabled={busy}>
              {busy ? 'Signing in…' : 'Sign in'}
            </button>
          </form>
          <div style={{ textAlign: 'center', marginTop: '16px', fontSize: '13px' }}>
            <a href="/forgot-password" style={{ color: 'var(--accent)' }}>
              Forgotten your password?
            </a>
          </div>
        </div>
      </div>
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
      case 'packages': return <Packages />;
      case 'enquiries': return <Enquiries />;
      case 'profile': return <Profile onSaved={setMe} />;
      default: return <Dashboard onNavigate={setActivePage} />;
    }
  };

  return (
    <div className="admin-layout">
      <aside className="sidebar">
        <div className="sidebar-logo">
          <img 
            src="/logo_2.png" 
            alt="nexARound" 
            className="sidebar-logo-img" 
            onError={(e) => { e.currentTarget.style.display = 'none'; }} 
          />
          <div>
            <div className="brand">nexARound</div>
            <div className="brand-sub">PARTNER PORTAL</div>
          </div>
        </div>

        <nav className="sidebar-nav">
          <div className="nav-section-label">Main Menu</div>
          {NAV.map(({ key, label, Icon }) => (
            <div
              key={key}
              className={`nav-item ${activePage === key ? 'active' : ''}`}
              onClick={() => setActivePage(key)}
            >
              <span className="icon"><Icon size={18} /></span>
              {label}
            </div>
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
          <button className="logout-btn" title="Sign out" onClick={handleLogout}>
            <LogOutIcon size={16} />
          </button>
        </div>
      </aside>

      <main className="main-content">
        <div className="page-header">
          <div className="page-title">{TITLES[activePage]}</div>
        </div>
        <div className="page-body">
          {/* A suspended vendor can still sign in and see why. Every write is
              refused server-side with a 403 regardless of this banner. */}
          {me && me.vendor_is_active === false && (
            <div className="login-error" style={{ marginBottom: '16px' }}>
              Your listing is currently hidden from travellers. Contact NexAround.
            </div>
          )}
          {renderContent()}
        </div>
      </main>
    </div>
  );
}
