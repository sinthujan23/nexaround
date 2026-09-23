import { useState } from 'react';
import { apiPost } from '../api';
import { AuthLayout } from '../components/Kit';

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
    <AuthLayout title="Forgotten your password?">
      {sent ? (
        <>
          <p className="auth-note">
            If that address has a partner account, a reset link is on its way.
            It is valid for one hour.
          </p>
          <a className="btn btn-ghost btn-block" href="/">Back to sign in</a>
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
          <button type="submit" className="btn btn-primary btn-block" disabled={busy}>
            {busy ? 'Sending…' : 'Send reset link'}
          </button>
          <div className="auth-link">
            <a href="/">Back to sign in</a>
          </div>
        </form>
      )}
    </AuthLayout>
  );
}
