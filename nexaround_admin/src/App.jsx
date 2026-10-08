import { useState, useEffect } from 'react';
import './index.css';
import { apiPost } from './api';
import Dashboard from './pages/Dashboard';
import Users from './pages/Users';
import Approvals from './pages/Approvals';
import Payments from './pages/Payments';
import Engagement from './pages/Engagement';
import Attractions from './pages/Attractions';
import ExcludeKeywords from './pages/ExcludeKeywords';
import Media from './pages/Media';
import Settings from './pages/Settings';
import ApiUsage from './pages/ApiUsage';
import Experiences from './pages/Experiences';
import ExperienceEnquiries from './pages/ExperienceEnquiries';
import ErrorBoundary from './components/ErrorBoundary';
import { CompassIcon, UsersIcon, MapPinIcon, CreditCardIcon, MegaphoneIcon, ImageIcon, SettingsIcon, ClipboardCheckIcon, TrendingUpIcon, EyeOffIcon, TicketIcon, InboxIcon, LogOutIcon } from './components/Icons';

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
            <img 
              src="/logo_2.png" 
              alt="nexARound" 
              className="login-logo-img" 
              onError={(e) => { e.currentTarget.style.display = 'none'; }} 
            />
            <div className="brand">nexARound</div>
            <p>Admin Portal</p>
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
      case 'experiences':
        return <Experiences />;
      case 'experienceenquiries':
        return <ExperienceEnquiries />;
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
      case 'experiences':
        return 'Experiences & Vendors';
      case 'experienceenquiries':
        return 'Experience Enquiries';
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
          <span className="logo-tile">
            <img 
              src="/logo_2.png" 
              alt="nexARound" 
              onError={(e) => { e.currentTarget.style.display = 'none'; }} 
            />
          </span>
          <div>
            <div className="brand">nexARound</div>
            <div className="brand-sub">ADMIN PORTAL</div>
          </div>
        </div>
        <nav className="sidebar-nav">
          <div className="nav-section-label">Main Menu</div>
          <button
            type="button"
            className={`nav-item ${activePage === 'dashboard' ? 'active' : ''}`}
            aria-current={activePage === 'dashboard' ? 'page' : undefined}
            onClick={() => setActivePage('dashboard')}
          >
            <span className="icon"><CompassIcon size={18} /></span> Dashboard
          </button>
          <button
            type="button"
            className={`nav-item ${activePage === 'attractions' ? 'active' : ''}`}
            aria-current={activePage === 'attractions' ? 'page' : undefined}
            onClick={() => setActivePage('attractions')}
          >
            <span className="icon"><MapPinIcon size={18} /></span> Attractions
          </button>
          <button
            type="button"
            className={`nav-item ${activePage === 'approvals' ? 'active' : ''}`}
            aria-current={activePage === 'approvals' ? 'page' : undefined}
            onClick={() => setActivePage('approvals')}
          >
            <span className="icon"><ClipboardCheckIcon size={18} /></span> Place Approvals
          </button>
          <button
            type="button"
            className={`nav-item ${activePage === 'excludekeywords' ? 'active' : ''}`}
            aria-current={activePage === 'excludekeywords' ? 'page' : undefined}
            onClick={() => setActivePage('excludekeywords')}
          >
            <span className="icon"><EyeOffIcon size={18} /></span> Exclude Keywords
          </button>
          <button
            type="button"
            className={`nav-item ${activePage === 'media' ? 'active' : ''}`}
            aria-current={activePage === 'media' ? 'page' : undefined}
            onClick={() => setActivePage('media')}
          >
            <span className="icon"><ImageIcon size={18} /></span> Media Library
          </button>
          
          <div className="nav-section-label" style={{ marginTop: '8px' }}>Business</div>
          <button
            type="button"
            className={`nav-item ${activePage === 'experiences' ? 'active' : ''}`}
            aria-current={activePage === 'experiences' ? 'page' : undefined}
            onClick={() => setActivePage('experiences')}
          >
            <span className="icon"><TicketIcon size={18} /></span> Experiences
          </button>
          <button
            type="button"
            className={`nav-item ${activePage === 'experienceenquiries' ? 'active' : ''}`}
            aria-current={activePage === 'experienceenquiries' ? 'page' : undefined}
            onClick={() => setActivePage('experienceenquiries')}
          >
            <span className="icon"><InboxIcon size={18} /></span> Enquiries
          </button>
          <button
            type="button"
            className={`nav-item ${activePage === 'payments' ? 'active' : ''}`}
            aria-current={activePage === 'payments' ? 'page' : undefined}
            onClick={() => setActivePage('payments')}
          >
            <span className="icon"><CreditCardIcon size={18} /></span> Payments & Plans
          </button>
          
          <div className="nav-section-label" style={{ marginTop: '8px' }}>System</div>
          <button
            type="button"
            className={`nav-item ${activePage === 'users' ? 'active' : ''}`}
            aria-current={activePage === 'users' ? 'page' : undefined}
            onClick={() => setActivePage('users')}
          >
            <span className="icon"><UsersIcon size={18} /></span> User Management
          </button>
          <button
            type="button"
            className={`nav-item ${activePage === 'engagement' ? 'active' : ''}`}
            aria-current={activePage === 'engagement' ? 'page' : undefined}
            onClick={() => setActivePage('engagement')}
          >
            <span className="icon"><MegaphoneIcon size={18} /></span> Engagement
          </button>
          <button
            type="button"
            className={`nav-item ${activePage === 'apiusage' ? 'active' : ''}`}
            aria-current={activePage === 'apiusage' ? 'page' : undefined}
            onClick={() => setActivePage('apiusage')}
          >
            <span className="icon"><TrendingUpIcon size={18} /></span> API Usage
          </button>
          <button
            type="button"
            className={`nav-item ${activePage === 'settings' ? 'active' : ''}`}
            aria-current={activePage === 'settings' ? 'page' : undefined}
            onClick={() => setActivePage('settings')}
          >
            <span className="icon"><SettingsIcon size={18} /></span> Settings
          </button>
        </nav>
        <div className="sidebar-footer">
          <div className="admin-user">
            <div className="admin-avatar">A</div>
            <div className="user-info" style={{ display: 'flex', flexDirection: 'column', minWidth: 0, flex: 1, gap: '2px' }}>
              <div className="admin-name" title="Admin">Admin</div>
              <div className="admin-role" title="Administrator">Administrator</div>
            </div>
          </div>
          <button className="logout-btn" title="Sign out" onClick={handleLogout}>
            <LogOutIcon size={16} />
          </button>
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
          <ErrorBoundary>
            {renderContent()}
          </ErrorBoundary>
        </div>
      </main>
    </div>
  );
}

export default App;
