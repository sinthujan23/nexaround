import { useState, useEffect } from 'react';
import './index.css';
import { apiPost } from './api';
import Dashboard from './pages/Dashboard';
import Users from './pages/Users';
import Approvals from './pages/Approvals';
import Payments from './pages/Payments';
import Engagement from './pages/Engagement';
import Attractions from './pages/Attractions';
import Categories from './pages/Categories';
import ExcludeKeywords from './pages/ExcludeKeywords';
import Media from './pages/Media';
import Settings from './pages/Settings';
import ApiUsage from './pages/ApiUsage';
import { CompassIcon, UsersIcon, MapPinIcon, CreditCardIcon, MegaphoneIcon, FolderIcon, ImageIcon, SettingsIcon, ClipboardCheckIcon, TrendingUpIcon, EyeOffIcon } from './components/Icons';

function App() {
  const [token, setToken] = useState(localStorage.getItem('admin_token'));
  const [activePage, setActivePage] = useState('dashboard');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const handleUnauthorized = (e) => {
      localStorage.removeItem('admin_token');
      setToken(null);
      setError(e.detail?.message || 'Session expired. Please sign in again.');
      setActivePage('dashboard');
    };

    window.addEventListener('auth:unauthorized', handleUnauthorized);
    return () => window.removeEventListener('auth:unauthorized', handleUnauthorized);
  }, []);

  const handleLogin = async (e) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const res = await apiPost('/admin/login', { username, password });
      if (res && res.token) {
        localStorage.setItem('admin_token', res.token);
        setToken(res.token);
      } else {
        setError('Unexpected response from server.');
      }
    } catch (err) {
      setError(err.message || 'Login failed. Please check your credentials.');
    } finally {
      setLoading(false);
    }
  };

  const handleLogout = () => {
    localStorage.removeItem('admin_token');
    setToken(null);
    setActivePage('dashboard');
  };

  if (!token) {
    return (
      <div className="login-page">
        <div className="login-card">
          <div className="login-logo">
            <div className="brand">NexARound</div>
            <p>NexARound Admin Portal</p>
          </div>
          {error && <div className="login-error">{error}</div>}
          <form onSubmit={handleLogin}>
            <div className="form-group">
              <label className="form-label">Username</label>
              <input
                type="text"
                className="form-input"
                placeholder="Enter admin username"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                required
              />
            </div>
            <div className="form-group">
              <label className="form-label">Password</label>
              <input
                type="password"
                className="form-input"
                placeholder="Enter password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
            </div>
            <button type="submit" className="btn btn-primary" style={{ width: '100%', marginTop: '10px' }} disabled={loading}>
              {loading ? 'Authenticating...' : 'Sign In'}
            </button>
          </form>
        </div>
      </div>
    );
  }

  const renderContent = () => {
    switch (activePage) {
      case 'dashboard':
        return <Dashboard />;
      case 'attractions':
        return <Attractions />;
      case 'categories':
        return <Categories />;
      case 'excludekeywords':
        return <ExcludeKeywords />;
      case 'media':
        return <Media />;
      case 'users':
        return <Users />;
      case 'approvals':
        return <Approvals />;
      case 'payments':
        return <Payments />;
      case 'engagement':
        return <Engagement />;
      case 'apiusage':
        return <ApiUsage />;
      case 'settings':
        return <Settings />;
      default:
        return <Dashboard />;
    }
  };

  const getPageTitle = () => {
    switch (activePage) {
      case 'dashboard':
        return 'Dashboard Overview';
      case 'attractions':
        return 'Manage Attractions';
      case 'categories':
        return 'Manage Categories';
      case 'excludekeywords':
        return 'Exclude Keywords';
      case 'media':
        return 'Media Library';
      case 'users':
        return 'Explorer Management';
      case 'approvals':
        return 'Place Approvals';
      case 'payments':
        return 'Payments & Plans';
      case 'engagement':
        return 'Engagement & Broadcasting';
      case 'apiusage':
        return 'API Usage & Cost';
      case 'settings':
        return 'General Settings';
      default:
        return 'Dashboard Overview';
    }
  };

  return (
    <div className="admin-layout">
      {/* Sidebar */}
      <aside className="sidebar">
        <div className="sidebar-logo">
          <div className="brand">nexARound</div>
          <div className="brand-sub">nexARound Admin</div>
        </div>
        <nav className="sidebar-nav">
          <div className="nav-section-label">Main Menu</div>
          <div className={`nav-item ${activePage === 'dashboard' ? 'active' : ''}`} onClick={() => setActivePage('dashboard')}>
            <CompassIcon className="icon" /> Dashboard
          </div>
          <div className={`nav-item ${activePage === 'attractions' ? 'active' : ''}`} onClick={() => setActivePage('attractions')}>
            <MapPinIcon className="icon" /> Attractions
          </div>
          <div className={`nav-item ${activePage === 'approvals' ? 'active' : ''}`} onClick={() => setActivePage('approvals')}>
            <ClipboardCheckIcon className="icon" /> Place Approvals
          </div>
          <div className={`nav-item ${activePage === 'categories' ? 'active' : ''}`} onClick={() => setActivePage('categories')}>
            <FolderIcon className="icon" /> Categories
          </div>
          <div className={`nav-item ${activePage === 'excludekeywords' ? 'active' : ''}`} onClick={() => setActivePage('excludekeywords')}>
            <EyeOffIcon className="icon" /> Exclude Keywords
          </div>
          <div className={`nav-item ${activePage === 'media' ? 'active' : ''}`} onClick={() => setActivePage('media')}>
            <ImageIcon className="icon" /> Media Library
          </div>
          
          <div className="nav-section-label" style={{ marginTop: '8px' }}>Business</div>
          <div className={`nav-item ${activePage === 'payments' ? 'active' : ''}`} onClick={() => setActivePage('payments')}>
            <CreditCardIcon className="icon" /> Payments & Plans
          </div>
          
          <div className="nav-section-label" style={{ marginTop: '8px' }}>System</div>
          <div className={`nav-item ${activePage === 'users' ? 'active' : ''}`} onClick={() => setActivePage('users')}>
            <UsersIcon className="icon" /> User Management
          </div>
          <div className={`nav-item ${activePage === 'engagement' ? 'active' : ''}`} onClick={() => setActivePage('engagement')}>
            <MegaphoneIcon className="icon" /> Engagement
          </div>
          <div className={`nav-item ${activePage === 'apiusage' ? 'active' : ''}`} onClick={() => setActivePage('apiusage')}>
            <TrendingUpIcon className="icon" /> API Usage
          </div>
          <div className={`nav-item ${activePage === 'settings' ? 'active' : ''}`} onClick={() => setActivePage('settings')}>
            <SettingsIcon className="icon" /> Settings
          </div>
        </nav>
        <div className="sidebar-footer">
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
              <div className="admin-avatar" style={{ width: '32px', height: '32px', fontSize: '12px' }}>A</div>
              <div className="user-info" style={{ display: 'flex', flexDirection: 'column' }}>
                <span className="admin-name" style={{ color: 'var(--text-primary)', fontWeight: 700, fontSize: '13px' }}>Admin</span>
                <span className="admin-role" style={{ fontSize: '10px', color: 'var(--text-secondary)' }}>Administrator</span>
              </div>
            </div>
            <button
              onClick={handleLogout}
              style={{
                border: 'none',
                background: 'rgba(229,57,53,0.08)',
                color: 'var(--danger)',
                padding: '8px',
                borderRadius: '8px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                cursor: 'pointer',
                transition: 'background 0.2s ease'
              }}
              title="Sign Out"
            >
              <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
                <polyline points="16 17 21 12 16 7" />
                <line x1="21" y1="12" x2="9" y2="12" />
              </svg>
            </button>
          </div>
        </div>
      </aside>

      {/* Main Content */}
      <main className="main-content">
        <header className="page-header">
          <div>
            <div className="page-title">{getPageTitle()}</div>
          </div>

        </header>

        <div className="page-body">
          {renderContent()}
        </div>
      </main>
    </div>
  );
}

export default App;
