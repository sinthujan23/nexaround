import { useEffect, useState } from 'react';
import { useApi, apiGet, apiPatch, mediaUrl } from '../api';
import { CheckIcon, CrossIcon, ImageIcon, MapPinIcon, RefreshIcon } from '../components/Icons';
import { EmptyState, Toast } from '../components/Kit';
import { useToast } from '../hooks';

// Photos travellers send for places that show only their category icon.
// Approving one shows it for that place to everyone at once; rejecting deletes
// the file.

const PAGE_SIZE = 24;
const STATUSES = [
  ['pending', 'Waiting'],
  ['approved', 'Approved'],
  ['rejected', 'Rejected'],
];
const TZ = 'Asia/Colombo';

const formatDateTime = (value) =>
  value
    ? new Date(value).toLocaleString('en-GB', {
      day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: TZ,
    })
    : '—';

const sourceOf = (key) => {
  if (key.startsWith('op_')) return 'Free map data (Overture)';
  if (key.startsWith('ga_')) return 'Free map data (OpenStreetMap)';
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-/i.test(key)) return 'Our map database';
  return 'Google';
};

export default function Media() {
  const [statusFilter, setStatusFilter] = useState('pending');
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState(null);
  const [saving, setSaving] = useState(false);
  const [counts, setCounts] = useState({});
  const [countsVersion, setCountsVersion] = useState(0);
  const [toast, notify] = useToast();

  const { data, error, refetch } = useApi(
    `/admin/place-photos?status=${statusFilter}&page=${page}&page_size=${PAGE_SIZE}`
  );
  const photos = data?.photos || [];
  const total = data?.total || 0;
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  useEffect(() => {
    let active = true;
    Promise.all(
      STATUSES.map(([s]) =>
        apiGet(`/admin/place-photos?status=${s}&page=1&page_size=1`)
          .then((res) => [s, res.total])
          .catch(() => [s, null])
      )
    ).then((pairs) => { if (active) setCounts(Object.fromEntries(pairs)); });
    return () => { active = false; };
  }, [countsVersion]);

  const refresh = () => {
    refetch();
    setCountsVersion((n) => n + 1);
  };

  const changeFilter = (s) => {
    setStatusFilter(s);
    setPage(1);
    setSelected(null);
  };

  const review = async (photo, status, message) => {
    let reason;
    if (status === 'rejected') {
      reason = prompt('Reject this photo? It will be deleted. Optional reason (the traveller sees it):', '');
      if (reason === null) return;
    }
    setSaving(true);
    try {
      await apiPatch(`/admin/place-photos/${photo.id}`, { status, reason: reason || null });
      setSelected(null);
      refresh();
      notify(message);
    } catch (err) {
      notify(`Could not update the photo: ${err.message}`, 'error');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div>
      <div className="xp-toolbar">
        <div className="seg">
          {STATUSES.map(([value, label]) => (
            <button
              key={value}
              className={`seg-btn ${statusFilter === value ? 'active' : ''}`}
              onClick={() => changeFilter(value)}
            >
              {label}
              {counts[value] != null && <span className="seg-count">{counts[value]}</span>}
            </button>
          ))}
        </div>
        <div className="xp-toolbar-right">
          <button className="btn btn-ghost btn-sm" onClick={refresh} title="Refresh">
            <RefreshIcon size={15} /> Refresh
          </button>
        </div>
      </div>

      {error && <div className="login-error">{error}</div>}

      {!data && <div className="loader" />}

      {data && photos.length === 0 && (
        <div className="card">
          <EmptyState icon={<ImageIcon size={28} />} title={statusFilter === 'pending' ? 'Nothing waiting' : 'No photos here yet'}>
            {statusFilter === 'pending'
              ? 'Travellers can add a photo to a place that shows only its category icon. New ones wait here for you.'
              : 'Photos you review show up here.'}
          </EmptyState>
        </div>
      )}

      {photos.length > 0 && (
        <div style={{
          display: 'grid', gap: 16,
          gridTemplateColumns: 'repeat(auto-fill, minmax(220px, 1fr))',
        }}>
          {photos.map((p) => (
            <div key={p.id} className="card" style={{ padding: 0, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
              <button
                onClick={() => setSelected(p)}
                style={{ padding: 0, border: 0, background: 'var(--surface-2, #f3f4f6)', cursor: 'zoom-in', aspectRatio: '4 / 3' }}
                title="Open"
              >
                {p.url
                  ? <img src={mediaUrl(p.url)} alt={p.place_name} style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
                  : <div style={{ display: 'grid', placeItems: 'center', height: '100%', color: 'var(--text-secondary)' }}>Deleted</div>}
              </button>
              <div style={{ padding: 12, display: 'flex', flexDirection: 'column', gap: 4, flex: 1 }}>
                <strong style={{ fontSize: 14 }}>{p.place_name}</strong>
                <span className="muted" style={{ fontSize: 12 }}>{sourceOf(p.place_key)}</span>
                <span className="muted" style={{ fontSize: 12 }}>By {p.uploader_name} · {formatDateTime(p.created_at)}</span>
                {p.reject_reason && <span style={{ fontSize: 12 }}>Reason: {p.reject_reason}</span>}
                <div style={{ display: 'flex', gap: 8, marginTop: 'auto', paddingTop: 8 }}>
                  {p.status === 'pending' && (
                    <button className="btn btn-primary btn-sm" disabled={saving}
                      onClick={() => review(p, 'approved', 'Photo approved')}>
                      <CheckIcon size={14} /> Approve
                    </button>
                  )}
                  {p.status !== 'rejected' && (
                    <button className="btn btn-danger-ghost btn-sm" disabled={saving}
                      onClick={() => review(p, 'rejected', p.status === 'approved' ? 'Photo taken down' : 'Photo rejected')}>
                      <CrossIcon size={14} /> {p.status === 'approved' ? 'Take down' : 'Reject'}
                    </button>
                  )}
                  {p.latitude != null && p.longitude != null && (
                    <a className="btn btn-ghost btn-sm" target="_blank" rel="noreferrer"
                      href={`https://www.google.com/maps/search/?api=1&query=${p.latitude},${p.longitude}`}
                      title="Open the place on the map">
                      <MapPinIcon size={14} />
                    </a>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {totalPages > 1 && (
        <div className="xp-list-foot" style={{ marginTop: 16 }}>
          <button className="btn btn-ghost btn-sm" disabled={page <= 1} onClick={() => setPage((n) => n - 1)}>Previous</button>
          <span>Page {page} of {totalPages}</span>
          <button className="btn btn-ghost btn-sm" disabled={page >= totalPages} onClick={() => setPage((n) => n + 1)}>Next</button>
        </div>
      )}

      {selected && selected.url && (
        <div
          onClick={() => setSelected(null)}
          style={{
            position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.8)', zIndex: 1000,
            display: 'grid', placeItems: 'center', padding: 24, cursor: 'zoom-out',
          }}
        >
          <img src={mediaUrl(selected.url)} alt={selected.place_name}
            style={{ maxWidth: '100%', maxHeight: '100%', borderRadius: 12 }} />
        </div>
      )}

      <Toast toast={toast} />
    </div>
  );
}
