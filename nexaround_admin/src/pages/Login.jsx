import { useState } from 'react';
import { apiPost } from '../api';

export default function Login({ initialError = '', onLogin }) {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [capsLockActive, setCapsLockActive] = useState(false);
  const [rememberMe, setRememberMe] = useState(true);
  const [error, setError] = useState(initialError);
  const [loading, setLoading] = useState(false);

  const handleKeyDown = (e) => {
    if (e.getModifierState) {
      setCapsLockActive(e.getModifierState('CapsLock'));
    }
  };

  const handleLogin = async (e) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const res = await apiPost('/admin/login', {
        username: username.trim(),
        password,
      });
      if (res && res.token) {
        onLogin(res.token);
      } else {
        setError('Unexpected response from server.');
      }
    } catch (err) {
      setError(err.message || 'Invalid username or password. Please verify your credentials.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="login-page">
      {/* LEFT PANEL: Clean Scenic Brand Backdrop */}
      <aside className="login-brand-panel" aria-label="nexARound Admin Portal">
        <div className="login-brand-overlay" />
        <div className="login-brand-content">
          <div className="login-brand-header">
            <div className="login-brand-logo-badge">
              <img
                src="/logo_2.png"
                alt="nexARound"
                className="login-brand-logo"
                onError={(e) => { e.currentTarget.style.display = 'none'; }}
              />
            </div>
            <div>
              <div className="login-brand-name">nexARound</div>
              <div className="login-brand-tagline">Admin Portal</div>
            </div>
          </div>
        </div>
      </aside>

      {/* RIGHT PANEL: Authentication Form */}
      <main className="login-form-panel">
        <div className="login-form-container">
          <div className="login-form-header">
            <div className="login-badge">Admin Gateway</div>
            <h2 className="login-welcome-title">Sign in to console</h2>
            <p className="login-welcome-subtitle">
              Enter your authorized administrator credentials to continue.
            </p>
          </div>

          {error && (
            <div className="login-error-alert" role="alert">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="10" />
                <line x1="12" y1="8" x2="12" y2="12" />
                <line x1="12" y1="16" x2="12.01" y2="16" />
              </svg>
              <span>{error}</span>
            </div>
          )}

          {capsLockActive && (
            <div className="login-caps-warning">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M12 2v10m0 0l-4-4m4 4l4-4M4 22h16" />
              </svg>
              <span>Caps Lock is ON</span>
            </div>
          )}

          <form onSubmit={handleLogin} className="login-form" noValidate>
            <div className="login-input-group">
              <label htmlFor="admin-username" className="login-input-label">Username</label>
              <div className="login-input-wrapper">
                <span className="login-input-icon">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
                    <circle cx="12" cy="7" r="4" />
                  </svg>
                </span>
                <input
                  id="admin-username"
                  name="username"
                  type="text"
                  autoComplete="username"
                  className="login-input"
                  placeholder="e.g. admin"
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  onKeyDown={handleKeyDown}
                  onKeyUp={handleKeyDown}
                  required
                />
              </div>
            </div>

            <div className="login-input-group">
              <div className="login-label-row">
                <label htmlFor="admin-password" className="login-input-label">Password</label>
              </div>
              <div className="login-input-wrapper">
                <span className="login-input-icon">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                    <path d="M7 11V7a5 5 0 0 1 10 0v4" />
                  </svg>
                </span>
                <input
                  id="admin-password"
                  name="password"
                  type={showPassword ? 'text' : 'password'}
                  autoComplete="current-password"
                  className="login-input login-input-password"
                  placeholder="Enter your security key"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  onKeyDown={handleKeyDown}
                  onKeyUp={handleKeyDown}
                  required
                />
                <button
                  type="button"
                  className="login-toggle-password"
                  onClick={() => setShowPassword(!showPassword)}
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                  tabIndex={-1}
                >
                  {showPassword ? (
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24" />
                      <line x1="1" y1="1" x2="23" y2="23" />
                    </svg>
                  ) : (
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" />
                      <circle cx="12" cy="12" r="3" />
                    </svg>
                  )}
                </button>
              </div>
            </div>

            <div className="login-options-row">
              <label className="login-checkbox-label">
                <input
                  type="checkbox"
                  checked={rememberMe}
                  onChange={(e) => setRememberMe(e.target.checked)}
                  className="login-checkbox"
                />
                <span>Remember this workstation</span>
              </label>
            </div>

            <button
              type="submit"
              className="login-submit-btn"
              disabled={loading || !username.trim() || !password}
            >
              {loading ? (
                <>
                  <span className="login-spinner" />
                  <span>Authenticating...</span>
                </>
              ) : (
                <>
                  <span>Sign In to Console</span>
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                    <line x1="5" y1="12" x2="19" y2="12" />
                    <polyline points="12 5 19 12 12 19" />
                  </svg>
                </>
              )}
            </button>
          </form>

          <footer className="login-footer">
            <p>&copy; {new Date().getFullYear()} nexARound Inc. All rights reserved.</p>
          </footer>
        </div>
      </main>
    </div>
  );
}

