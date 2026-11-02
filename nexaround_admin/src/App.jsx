import { useState, useEffect, startTransition } from 'react';
import { Navigate, Route, Routes, useLocation, useNavigate } from 'react-router-dom';
import './index.css';
import { apiGet, apiPost } from './api';
import { NAV_ITEMS, NAV_REDIRECTS, LOGIN_PATH, canSee, homePathFor } from './nav';
import { sessionRole, tokenExpired } from './session';
import Login from './pages/Login';
import AdminLayout from './components/layout/AdminLayout';
import NetworkStatusBar from './components/NetworkStatusBar';
import { PageLoading } from './components/Kit';

const EXPIRED = 'Session expired. Please sign in again.';

// The token saved on this device when the page opened. One whose expiry time
// has already passed never opens the panel: it goes straight to sign-in.
function savedSignIn() {
  const saved = localStorage.getItem('admin_token');
  const expired = Boolean(saved) && tokenExpired(saved);
  return { token: expired ? null : saved, error: expired ? EXPIRED : '' };
}

function App() {
  const navigate = useNavigate();
  const location = useLocation();
  const [start] = useState(savedSignIn);
  const [token, setToken] = useState(start.token);
  const [error, setError] = useState(start.error);
  // A token that hasn't run out can still be dead (signed out from Devices &
  // Sessions, a creator's login switched off), so the server confirms it
  // before any page shows. A token fresh from the sign-in form needs no check.
  const [checking, setChecking] = useState(start.token !== null);

  useEffect(() => {
    if (start.error) localStorage.removeItem('admin_token');
  }, [start]);

  // Signed out, every URL redirects to /login and remembers the page in
  // state.from, so signing in (e.g. after an expired session) returns to it.
  useEffect(() => {
    const handleUnauthorized = (e) => {
      localStorage.removeItem('admin_token');
      setToken(null);
      setError(e.detail?.message || 'Session expired. Please sign in again.');
    };

    window.addEventListener('auth:unauthorized', handleUnauthorized);
    return () => window.removeEventListener('auth:unauthorized', handleUnauthorized);
  }, []);

  // A 401 signs out through auth:unauthorized above (registered first). Any
  // other failure (offline, server error) opens the panel: its pages show
  // their own errors.
  useEffect(() => {
    if (!checking) return undefined;
    let current = true;
    apiGet('/admin/session')
      .catch(() => {})
      .finally(() => {
        if (current) setChecking(false);
      });
    return () => {
      current = false;
    };
  }, [checking]);

  // No navigate() here: the signed-in /login route below does the redirect.
  const handleLogin = (newToken) => {
    localStorage.setItem('admin_token', newToken);
    setError('');
    setToken(newToken);
  };

  // React Router applies navigate() in a transition. Clearing the token in the
  // same transition means the signed-out routes first render at /login, so the
  // page being left isn't remembered and signing back in lands on HOME_PATH.
  const handleLogout = () => {
    // Revokes this device's session on the server so the token stops working
    // at once. Best effort and not awaited: signing out must never hang on it.
    apiPost('/admin/logout').catch(() => {});
    localStorage.removeItem('admin_token');
    startTransition(() => setToken(null));
    navigate(LOGIN_PATH, { replace: true });
  };

  if (!token) {
    return (
      <>
        <NetworkStatusBar />
        <Routes>
          <Route path={LOGIN_PATH} element={<Login initialError={error} onLogin={handleLogin} />} />
          <Route
            path="*"
            element={<Navigate to={LOGIN_PATH} replace state={{ from: location.pathname + location.search }} />}
          />
        </Routes>
      </>
    );
  }

  if (checking) {
    return (
      <>
        <NetworkStatusBar />
        <div style={{ minHeight: '100vh', display: 'grid', placeItems: 'center' }}>
          <PageLoading />
        </div>
      </>
    );
  }

  // A content creator's token opens City Tours only; any other address lands there.
  const role = sessionRole();
  const home = homePathFor(role);

  return (
    <>
      <NetworkStatusBar />
      <Routes>
        <Route path={LOGIN_PATH} element={<Navigate to={location.state?.from || home} replace />} />
        <Route element={<AdminLayout onLogout={handleLogout} />}>
          {NAV_ITEMS.filter((item) => canSee(item, role)).map(({ path, page: Page }) => (
            <Route key={path} path={path} element={<Page />} />
          ))}
          {NAV_REDIRECTS.map(([from, to]) => (
            <Route key={from} path={from} element={<Navigate to={to} replace />} />
          ))}
          <Route path="*" element={<Navigate to={home} replace />} />
        </Route>
      </Routes>
    </>
  );
}

export default App;
