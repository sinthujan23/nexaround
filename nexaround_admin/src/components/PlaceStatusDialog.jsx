import { useState } from 'react';
import { Modal } from './Kit';
import { REASONS } from '../places';

/**
 * Ask why a place is being hidden or rejected. The reason is stored with the
 * place, so the next admin can see why it isn't in the app.
 */
export default function PlaceStatusDialog({
  title, intro, confirmLabel, defaultReason = '', onConfirm, onClose,
}) {
  const [reason, setReason] = useState(defaultReason);
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const submit = async (e) => {
    e.preventDefault();
    if (!reason) { setError('Choose a reason.'); return; }
    if (reason === 'other' && !note.trim()) { setError('Write a short note for "Other".'); return; }
    setBusy(true);
    setError('');
    try {
      await onConfirm(reason, note.trim());
    } catch (err) {
      setError(err.message || 'Something went wrong.');
      setBusy(false);
    }
  };

  return (
    <Modal title={title} onClose={onClose} maxWidth="460px">
      <form onSubmit={submit}>
        {intro && <p style={{ margin: '0 0 16px', fontSize: '13px', color: 'var(--text-secondary)' }}>{intro}</p>}
        <div className="form-group">
          <label className="form-label">Reason</label>
          <select className="form-select" value={reason} onChange={(e) => setReason(e.target.value)} autoFocus>
            <option value="">Choose…</option>
            {REASONS.map(([code, label]) => <option key={code} value={code}>{label}</option>)}
          </select>
        </div>
        <div className="form-group">
          <label className="form-label">Note {reason === 'other' ? '' : '(optional)'}</label>
          <textarea
            className="form-textarea" rows={3} maxLength={2000}
            value={note} onChange={(e) => setNote(e.target.value)}
          />
        </div>
        {error && <div className="login-error" style={{ marginBottom: '12px' }}>{error}</div>}
        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '8px' }}>
          <button type="button" className="btn btn-ghost" onClick={onClose} disabled={busy}>Cancel</button>
          <button type="submit" className="btn btn-primary" disabled={busy}>
            {busy ? 'Saving…' : confirmLabel}
          </button>
        </div>
      </form>
    </Modal>
  );
}
