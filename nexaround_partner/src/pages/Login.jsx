import { useState } from 'react';
import { Link, Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '../auth';
import { AuthLayout } from '../components/Kit';

export default function Login() {
  const { token, notice, login } = useAuth();
  const location = useLocation();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  // Signed in (or just signed in): go where they were headed.
  if (token) return <Navigate to={location.state?.from || '/dashboard'} replace />;

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      await login(email, password);
    } catch (err) {
      setError(err.message || 'Could not sign in.');
      setBusy(false);
    }
  };

  const shown = error || notice;

  return (
    <AuthLayout title="Sign in">
      {shown && <div className="login-error">{shown}</div>}
      <form onSubmit={submit}>
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
        <Link to="/forgot-password">Forgotten your password?</Link>
      </div>
    </AuthLayout>
  );
}
