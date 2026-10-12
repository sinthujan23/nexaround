import { useState, useEffect, startTransition } from 'react';
import { Navigate, Route, Routes, useLocation, useNavigate } from 'react-router-dom';
import './index.css';
import { NAV_ITEMS, HOME_PATH, LOGIN_PATH } from './nav';
import Login from './pages/Login';
import AdminLayout from './components/layout/AdminLayout';

function App() {
  const navigate = useNavigate();
  const location = useLocation();
  const [token, setToken] = useState(localStorage.getItem('admin_token'));
  const [error, setError] = useState('');

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
    localStorage.removeItem('admin_token');
    startTransition(() => setToken(null));
    navigate(LOGIN_PATH, { replace: true });
  };

  if (!token) {
    return (
      <Routes>
        <Route path={LOGIN_PATH} element={<Login initialError={error} onLogin={handleLogin} />} />
        <Route
          path="*"
          element={<Navigate to={LOGIN_PATH} replace state={{ from: location.pathname + location.search }} />}
        />
      </Routes>
    );
  }

  return (
    <Routes>
      <Route path={LOGIN_PATH} element={<Navigate to={location.state?.from || HOME_PATH} replace />} />
      <Route element={<AdminLayout onLogout={handleLogout} />}>
        {NAV_ITEMS.map(({ path, page: Page }) => (
          <Route key={path} path={path} element={<Page />} />
        ))}
        <Route path="*" element={<Navigate to={HOME_PATH} replace />} />
      </Route>
    </Routes>
  );
}

export default App;
