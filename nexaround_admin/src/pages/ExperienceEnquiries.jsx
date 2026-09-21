import { useState } from 'react';
import { useApi, apiPatch } from '../api';
import { InboxIcon } from '../components/Icons';

const STATUSES = ['new', 'contacted', 'closed', 'spam'];

const STATUS_BADGE = {
  new: 'badge-yellow',
  contacted: 'badge-green',
  closed: 'badge-ghost',
  spam: 'badge-red',
};

const formatDate = (value) => {
  if (!value) return '—';
  return new Date(value).toLocaleString('en-GB', {
    day: '2-digit', month: 'short', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
    timeZone: 'Asia/Colombo',
  });
};

export default function ExperienceEnquiries() {
  const [statusFilter, setStatusFilter] = useState('');
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState(null);
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);

  const { data, loading, error, refetch } = useApi(
    `/admin/experiences/enquiries?page=${page}&page_size=25` +
    (statusFilter ? `&status=${statusFilter}` : '')
  );

  const enquiries = data?.enquiries || [];
  const total = data?.total || 0;
  const totalPages = Math.ceil(total / 25) || 1;

  const open = (enquiry) => {
    setSelected(enquiry);
    setNotes(enquiry.admin_notes || '');
  };

  const update = async (patch) => {
    if (!selected) return;
    setSaving(true);
    try {
      const updated = await apiPatch(`/admin/experiences/enquiries/${selected.id}`, patch);
      setSelected(updated);
      refetch();
    } catch (err) {
      alert(`Failed to update enquiry: ${err.message}`);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div>
      <div style={{ display: 'flex', gap: '10px', marginBottom: '20px', alignItems: 'center' }}>
        <select
          className="form-select"
          style={{ maxWidth: '200px' }}
          value={statusFilter}
          onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }}
        >
          <option value="">All statuses</option>
          {STATUSES.map((s) => (
            <option key={s} value={s}>{s[0].toUpperCase() + s.slice(1)}</option>
          ))}
        </select>
        <div style={{ color: 'var(--text-secondary)', fontSize: '14px' }}>
          {total} enquir{total === 1 ? 'y' : 'ies'}
        </div>
      </div>

      {error && <div className="login-error">{error}</div>}
      {loading && <div className="loader" />}

      {!loading && enquiries.length === 0 && (
        <div className="empty-state">
          <InboxIcon size={32} className="empty-icon" />
          <div>No enquiries yet. They appear here the moment a traveller sends one.</div>
        </div>
      )}

      {!loading && enquiries.length > 0 && (
        <div className="card">
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Received</th>
                  <th>Experience</th>
                  <th>Vendor</th>
                  <th>Traveller</th>
                  <th>Phone</th>
                  <th>Party</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {enquiries.map((enquiry) => (
                  <tr
                    key={enquiry.id}
                    className={`clickable-row ${selected?.id === enquiry.id ? 'selected' : ''}`}
                    onClick={() => open(enquiry)}
                  >
                    <td style={{ whiteSpace: 'nowrap' }}>{formatDate(enquiry.created_at)}</td>
                    <td><strong>{enquiry.package_title_snapshot || '—'}</strong></td>
                    <td style={{ color: 'var(--text-secondary)' }}>
                      {enquiry.vendor_name_snapshot || '—'}
                    </td>
                    <td>{enquiry.contact_name}</td>
                    <td>{enquiry.contact_phone}</td>
                    <td>{enquiry.party_size ?? '—'}</td>
                    <td>
                      <span className={`badge ${STATUS_BADGE[enquiry.status] || 'badge-ghost'}`}>
                        {enquiry.status}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '16px' }}>
            <button
              className="btn btn-ghost" disabled={page <= 1}
              onClick={() => setPage((p) => Math.max(1, p - 1))}
            >
              Previous
            </button>
            <span style={{ color: 'var(--text-secondary)', fontSize: '14px' }}>
              Page {page} of {totalPages}
            </span>
            <button
              className="btn btn-ghost" disabled={page >= totalPages}
              onClick={() => setPage((p) => p + 1)}
            >
              Next
            </button>
          </div>
        </div>
      )}

      {selected && (
        <div className="modal-overlay" onClick={() => setSelected(null)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <div className="card-header">
              <div className="card-title">{selected.package_title_snapshot || 'Enquiry'}</div>
            </div>

            <div style={{ color: 'var(--text-secondary)', fontSize: '14px', marginBottom: '16px' }}>
              {selected.vendor_name_snapshot} · {formatDate(selected.created_at)}
            </div>

            <div className="form-grid-2">
              <div className="form-group">
                <label className="form-label">Traveller</label>
                <div>{selected.contact_name}</div>
              </div>
              <div className="form-group">
                <label className="form-label">Party size</label>
                <div>{selected.party_size ?? '—'}</div>
              </div>
            </div>

            <div className="form-grid-2">
              <div className="form-group">
                <label className="form-label">Phone</label>
                <div style={{ display: 'flex', gap: '8px', alignItems: 'center', flexWrap: 'wrap' }}>
                  <a href={`tel:${selected.contact_phone}`} className="btn btn-ghost">Call</a>
                  <a
                    href={`https://wa.me/${(selected.contact_phone || '').replace(/[^0-9]/g, '')}`}
                    target="_blank" rel="noreferrer" className="btn btn-ghost"
                  >
                    WhatsApp
                  </a>
                </div>
              </div>
              <div className="form-group">
                <label className="form-label">Preferred date</label>
                <div>{selected.preferred_date || '—'}</div>
              </div>
            </div>

            {selected.contact_email && (
              <div className="form-group">
                <label className="form-label">Email</label>
                <a href={`mailto:${selected.contact_email}`}>{selected.contact_email}</a>
              </div>
            )}

            {selected.message && (
              <div className="form-group">
                <label className="form-label">Message</label>
                <div style={{
                  background: 'var(--bg-dark)', borderRadius: '10px',
                  padding: '12px 14px', color: 'var(--text-primary)',
                }}>
                  {selected.message}
                </div>
              </div>
            )}

            <div className="form-group">
              <label className="form-label">Status</label>
              <select
                className="form-select" value={selected.status} disabled={saving}
                onChange={(e) => update({ status: e.target.value })}
              >
                {STATUSES.map((s) => (
                  <option key={s} value={s}>{s[0].toUpperCase() + s.slice(1)}</option>
                ))}
              </select>
            </div>

            <div className="form-group">
              <label className="form-label">Internal notes</label>
              <textarea
                className="form-textarea" rows={3} value={notes}
                onChange={(e) => setNotes(e.target.value)}
              />
            </div>

            <div style={{ display: 'flex', gap: '10px' }}>
              <button
                className="btn btn-primary" disabled={saving}
                onClick={() => update({ admin_notes: notes })}
              >
                {saving ? 'Saving…' : 'Save notes'}
              </button>
              <button className="btn btn-ghost" onClick={() => setSelected(null)}>Close</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
