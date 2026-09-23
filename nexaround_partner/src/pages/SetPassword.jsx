import { useEffect, useState } from 'react';
import { apiGet, apiPost } from '../api';

/**
 * Where an invite or reset link lands. Renders without a token, on purpose:
 * this is the first page any vendor ever sees.
 */
export default function SetPassword() {
  const token = new URLSearchParams(window.location.search).get('token') || '';
  // A link with no token needs no round trip, so that case is derived rather
  // than set from an effect — setState in an effect body causes a cascading
  // render, and React flags it.
  const [checking, setChecking] = useState(Boolean(token));
  const [serverError, setServerError] = useState('');
  const linkError = token
    ? serverError
    : 'This link is missing its code. Ask NexAround to send a new one.';
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [error, setError] = useState('');
  const [done, setDone] = useState(false);
  const [busy, setBusy] = useState(false);

  // Asked up front so an expired link says so before anyone types a password.
  // This check does not consume the token.
  useEffect(() => {
    if (!token) return;
    apiGet(`/partner/auth/check-token?token=${encodeURIComponent(token)}`)
      .catch((err) => setServerError(err.message || 'This link is no longer valid.'))
      .finally(() => setChecking(false));
  }, [token]);

  const submit = async (e) => {
    e.preventDefault();
    if (password !== confirm) {
      setError('The two passwords do not match.');
      return;
    }
    if (password.length < 8) {
      setError('Use at least 8 characters.');
      return;
    }
    setBusy(true);
    setError('');
    try {
      await apiPost('/partner/auth/set-password', { token, new_password: password });
      setDone(true);
    } catch (err) {
      setError(err.message || 'Could not set the password.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="login-logo">nexARround</div>
        <div style={{ textAlign: 'center', color: 'var(--text-secondary)', marginBottom: '20px' }}>
          Partner portal
        </div>

        {checking && <div className="loader" />}

        {!checking && linkError && (
          <>
            <div className="login-error">{linkError}</div>
            <div style={{ fontSize: '13px', color: 'var(--text-secondary)', marginTop: '12px' }}>
              Links can only be used once, and expire. Ask NexAround to send another.
            </div>
          </>
        )}

        {!checking && !linkError && done && (
          <>
            <div style={{ textAlign: 'center', marginBottom: '16px' }}>
              Your password is set.
            </div>
            <a className="btn btn-primary" href="/" style={{ width: '100%', textAlign: 'center' }}>
              Sign in
            </a>
          </>
        )}

        {!checking && !linkError && !done && (
          <form onSubmit={submit}>
            <div className="form-group">
              <label className="form-label">New password</label>
              <input
                type="password" required className="form-input" autoComplete="new-password"
                value={password} onChange={(e) => setPassword(e.target.value)}
              />
            </div>
            <div className="form-group">
              <label className="form-label">Confirm password</label>
              <input
                type="password" required className="form-input" autoComplete="new-password"
                value={confirm} onChange={(e) => setConfirm(e.target.value)}
              />
            </div>
            {error && <div className="login-error">{error}</div>}
            <button type="submit" className="btn btn-primary" style={{ width: '100%' }} disabled={busy}>
              {busy ? 'Saving…' : 'Set password'}
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
