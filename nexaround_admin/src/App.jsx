import { useState, useEffect } from 'react';
import { Navigate, Route, Routes, useNavigate } from 'react-router-dom';
import './index.css';
import { NAV_ITEMS, HOME_PATH } from './nav';
import Login from './pages/Login';
import AdminLayout from './components/layout/AdminLayout';

function App() {
  const navigate = useNavigate();
  const [token, setToken] = useState(localStorage.getItem('admin_token'));
  const [error, setError] = useState('');

  // An expired session keeps the URL, so signing back in returns to the same page.
  useEffect(() => {
    const handleUnauthorized = (e) => {
      localStorage.removeItem('admin_token');
      setToken(null);
      setError(e.detail?.message || 'Session expired. Please sign in again.');
    };

    window.addEventListener('auth:unauthorized', handleUnauthorized);
    return () => window.removeEventListener('auth:unauthorized', handleUnauthorized);
  }, []);

  const handleLogin = (newToken) => {
    localStorage.setItem('admin_token', newToken);
    setError('');
    setToken(newToken);
  };

  const handleLogout = () => {
    localStorage.removeItem('admin_token');
    setToken(null);
    navigate(HOME_PATH);
  };

  if (!token) {
    return <Login initialError={error} onLogin={handleLogin} />;
  }

  return (
    <Routes>
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
