import { useState } from 'react';
import { apiPost } from '../api';

/**
 * Asks for a reset link.
 *
 * The success message is shown whatever the server said, because the server
 * deliberately answers identically whether or not the address exists — saying
 * "no such account" here would enumerate the vendor roster.
 */
export default function ForgotPassword() {
  const [email, setEmail] = useState('');
  const [sent, setSent] = useState(false);
  const [busy, setBusy] = useState(false);

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true);
    try {
      await apiPost('/partner/auth/forgot-password', { email });
    } catch {
      // Swallowed on purpose: a failure here must look like a success, or the
      // difference tells the caller whether the address is registered.
    } finally {
      setBusy(false);
      setSent(true);
    }
  };

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="login-logo">nexARround</div>
        <div style={{ textAlign: 'center', color: 'var(--text-secondary)', marginBottom: '20px' }}>
          Partner portal
        </div>

        {sent ? (
          <>
            <div style={{ textAlign: 'center', marginBottom: '16px' }}>
              If that address has a partner account, a reset link is on its way.
              It is valid for one hour.
            </div>
            <a className="btn btn-ghost" href="/" style={{ width: '100%', textAlign: 'center' }}>
              Back to sign in
            </a>
          </>
        ) : (
          <form onSubmit={submit}>
            <div className="form-group">
              <label className="form-label">Your email</label>
              <input
                type="email" required className="form-input" autoComplete="username"
                value={email} onChange={(e) => setEmail(e.target.value)}
              />
            </div>
            <button type="submit" className="btn btn-primary" style={{ width: '100%' }} disabled={busy}>
              {busy ? 'Sending…' : 'Send reset link'}
            </button>
            <div style={{ textAlign: 'center', marginTop: '16px', fontSize: '13px' }}>
              <a href="/" style={{ color: 'var(--accent)' }}>Back to sign in</a>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}
