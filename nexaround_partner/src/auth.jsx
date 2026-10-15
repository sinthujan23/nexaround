import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { apiGet, apiPost } from './api';

const AuthContext = createContext(null);

/**
 * Who is signed in. Lives above the router's pages so the shell, the pages and
 * the sign-in screen all read the same token and vendor.
 *
 * `api.js` fires `auth:unauthorized` on any 401 and the live stream fires it
 * when the server ends the session; both land here, clear the token, and the
 * route guard sends the vendor to /login with the reason shown.
 */
export function AuthProvider({ children }) {
  const [token, setToken] = useState(() => localStorage.getItem('partner_token'));
  const [me, setMe] = useState(null);
  const [notice, setNotice] = useState('');

  useEffect(() => {
    const onUnauthorized = (e) => {
      localStorage.removeItem('partner_token');
      setToken(null);
      setMe(null);
      setNotice(e.detail?.message || 'Session expired. Please sign in again.');
    };
    window.addEventListener('auth:unauthorized', onUnauthorized);
    return () => window.removeEventListener('auth:unauthorized', onUnauthorized);
  }, []);

  // The sidebar and the suspension banner need the vendor. A failure is
  // already handled: apiGet fires auth:unauthorized on a 401.
  useEffect(() => {
    if (!token) return;
    apiGet('/partner/me').then(setMe).catch(() => {});
  }, [token]);

  const refreshMe = useCallback(() => apiGet('/partner/me').then(setMe).catch(() => {}), []);

  const login = useCallback(async (email, password) => {
    const res = await apiPost('/partner/auth/login', { email, password });
    localStorage.setItem('partner_token', res.access_token);
    setNotice('');
    setToken(res.access_token);
    setMe(res.me);
  }, []);

  const logout = useCallback(() => {
    // Tell the server so the session is revoked, but do not wait on it: the
    // vendor is signed out of this browser either way.
    apiPost('/partner/auth/logout', {}).catch(() => {});
    localStorage.removeItem('partner_token');
    setToken(null);
    setMe(null);
    setNotice('');
  }, []);

  return (
    <AuthContext.Provider value={{ token, me, setMe, refreshMe, notice, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components
export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth needs an AuthProvider');
  return ctx;
}

/** Wraps every page that needs a signed-in vendor. */
export function RequireAuth({ children }) {
  const { token } = useAuth();
  const location = useLocation();
  if (!token) {
    return <Navigate to="/login" replace state={{ from: location.pathname + location.search }} />;
  }
  return children;
}
