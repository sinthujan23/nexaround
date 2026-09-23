import { useState } from 'react';
import { useApi, apiPatch } from '../api';
import { InboxIcon } from '../components/Icons';

const STATUSES = ['new', 'contacted', 'closed'];
const COLOMBO = { timeZone: 'Asia/Colombo', dateStyle: 'medium', timeStyle: 'short' };

const badgeFor = (s) =>
  s === 'new' ? 'badge-yellow' : s === 'contacted' ? 'badge-green' : 'badge-ghost';

export default function Enquiries() {
  const [page, setPage] = useState(1);
  const [statusFilter, setStatusFilter] = useState('');
  const [selected, setSelected] = useState(null);
  const [notes, setNotes] = useState('');
  const [busy, setBusy] = useState(false);

  const { data, loading, error, refetch } = useApi(
    `/partner/enquiries?page=${page}&page_size=25${statusFilter ? `&status=${statusFilter}` : ''}`
  );
  const enquiries = data?.enquiries || [];
  const totalPages = Math.max(1, Math.ceil((data?.total || 0) / 25));

  const open = (e) => {
    setSelected(e);
    setNotes(e.vendor_notes || '');
  };

  const patch = async (body) => {
    setBusy(true);
    try {
      const updated = await apiPatch(`/partner/enquiries/${selected.id}`, body);
      setSelected(updated);
      refetch();
    } catch (err) {
      alert(`Could not save: ${err.message}`);
    } finally {
      setBusy(false);
    }
  };

  // Digits only: wa.me rejects spaces, dashes and a leading +.
  const waNumber = (phone) => (phone || '').replace(/\D/g, '');

  return (
    <>
      {error && <div className="login-error">{error}</div>}

      <div className="card" style={{ padding: '24px' }}>
        <div className="card-header">
          <div className="card-title">Enquiries ({data?.total ?? 0})</div>
          <select
            className="form-select" style={{ maxWidth: '200px' }}
            value={statusFilter}
            onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }}
          >
            <option value="">All statuses</option>
            {STATUSES.map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
        </div>

        {loading && <div className="loader" />}

        {!loading && enquiries.length === 0 && (
          <div className="empty-state">
            <InboxIcon size={32} className="empty-icon" />
            <div>Nothing here yet.</div>
          </div>
        )}

        {!loading && enquiries.length > 0 && (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Received</th>
                  <th>Package</th>
                  <th>Traveller</th>
                  <th>Phone</th>
                  <th>Party</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {enquiries.map((e) => (
                  <tr key={e.id} className="clickable-row" onClick={() => open(e)}>
                    <td>{e.created_at ? new Date(e.created_at).toLocaleString('en-GB', COLOMBO) : ''}</td>
                    <td>{e.package_title_snapshot || '—'}</td>
                    <td>{e.contact_name}</td>
                    <td>{e.contact_phone}</td>
                    <td>{e.party_size ?? '—'}</td>
                    <td><span className={`badge ${badgeFor(e.status)}`}>{e.status}</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {totalPages > 1 && (
          <div style={{ display: 'flex', gap: '10px', marginTop: '16px', alignItems: 'center' }}>
            <button className="btn btn-ghost" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
              Previous
            </button>
            <span style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>
              Page {page} of {totalPages}
            </span>
            <button className="btn btn-ghost" disabled={page >= totalPages} onClick={() => setPage((p) => p + 1)}>
              Next
            </button>
          </div>
        )}
      </div>

      {selected && (
        <div className="modal-overlay" onClick={() => setSelected(null)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <div className="card-header">
              <div className="card-title">{selected.contact_name}</div>
            </div>

            <div style={{ fontSize: '13px', color: 'var(--text-secondary)', marginBottom: '12px' }}>
              {selected.package_title_snapshot || 'General enquiry'}
              {selected.party_size ? ` · party of ${selected.party_size}` : ''}
              {selected.preferred_date ? ` · prefers ${selected.preferred_date}` : ''}
            </div>

            {/* The whole job: get the vendor talking to the traveller. */}
            <div style={{ display: 'flex', gap: '10px', marginBottom: '16px', flexWrap: 'wrap' }}>
              <a className="btn btn-primary" href={`tel:${selected.contact_phone}`}>
                Call {selected.contact_phone}
              </a>
              <a
                className="btn btn-ghost"
                href={`https://wa.me/${waNumber(selected.contact_phone)}`}
                target="_blank" rel="noreferrer"
              >
                WhatsApp
              </a>
              {selected.contact_email && (
                <a className="btn btn-ghost" href={`mailto:${selected.contact_email}`}>
                  Email
                </a>
              )}
            </div>

            {selected.message && (
              <div className="form-group">
                <label className="form-label">Their message</label>
                <div style={{
                  background: 'var(--code-bg, #f1f5f9)', borderRadius: '10px',
                  padding: '12px', fontSize: '13px', whiteSpace: 'pre-wrap',
                }}>
                  {selected.message}
                </div>
              </div>
            )}

            <div className="form-group">
              <label className="form-label">Status</label>
              <select
                className="form-select" value={selected.status} disabled={busy}
                onChange={(e) => patch({ status: e.target.value })}
              >
                {STATUSES.map((s) => <option key={s} value={s}>{s}</option>)}
              </select>
            </div>

            <div className="form-group">
              <label className="form-label">Your notes</label>
              <textarea
                className="form-textarea" rows={3} value={notes}
                onChange={(e) => setNotes(e.target.value)}
                placeholder="Only you and NexAround see this."
              />
            </div>

            <div style={{ display: 'flex', gap: '10px', marginTop: '8px' }}>
              <button className="btn btn-primary" disabled={busy} onClick={() => patch({ vendor_notes: notes })}>
                {busy ? 'Saving…' : 'Save notes'}
              </button>
              <button className="btn btn-ghost" onClick={() => setSelected(null)}>Close</button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
