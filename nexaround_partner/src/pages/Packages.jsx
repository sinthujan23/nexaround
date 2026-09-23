import { useState } from 'react';
import { useApi, apiPost, apiPut, apiDelete } from '../api';
import { PlusIcon, EditIcon, TrashIcon, TicketIcon } from '../components/Icons';
import LocationPicker from '../components/LocationPicker';
import ImageUploader from '../components/ImageUploader';

const CATEGORIES = [
  { value: 'boat', label: 'Boat ride' },
  { value: 'water_sports', label: 'Water sports' },
  { value: 'guided_tour', label: 'Guided tour' },
  { value: 'wildlife', label: 'Wildlife' },
  { value: 'cultural', label: 'Cultural' },
  { value: 'adventure', label: 'Adventure' },
  { value: 'food', label: 'Food' },
  { value: 'other', label: 'Other' },
];

const PRICE_BASES = [
  { value: 'per_person', label: 'Per person' },
  { value: 'per_group', label: 'Per group' },
  { value: 'from', label: 'Starting from' },
  { value: 'on_request', label: 'On request' },
];

const empty = {
  title: '', summary: '', description: '', category: 'boat', tags: [],
  photo_urls: [], price_amount: '', price_currency: 'LKR',
  price_basis: 'per_person', duration_minutes: '', max_participants: '',
  inclusions: [], languages: [], uses_vendor_location: true,
  meeting_point_address: '', is_active: true, latitude: null, longitude: null,
};

const linesToArray = (t) => t.split('\n').map((l) => l.trim()).filter(Boolean);
const arrayToLines = (a) => (a || []).join('\n');

export default function Packages() {
  // The shared hook rather than a hand-rolled loader: it owns the
  // loading/error/refetch dance, and calling setState straight from an effect
  // body is what React flags as a cascading render.
  const { data, loading, error, refetch } = useApi('/partner/packages');
  const packages = data?.packages || [];
  const [modalOpen, setModalOpen] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [form, setForm] = useState(empty);
  const [saving, setSaving] = useState(false);

  const openNew = () => { setEditingId(null); setForm(empty); setModalOpen(true); };
  const openEdit = (pkg) => {
    setEditingId(pkg.id);
    setForm({
      ...empty, ...pkg,
      price_amount: pkg.price_amount ?? '',
      duration_minutes: pkg.duration_minutes ?? '',
      max_participants: pkg.max_participants ?? '',
    });
    setModalOpen(true);
  };

  const save = async (e) => {
    e.preventDefault();
    const payload = {
      ...form,
      price_amount: form.price_amount === '' ? null : Number(form.price_amount),
      duration_minutes: form.duration_minutes === '' ? null : Number(form.duration_minutes),
      max_participants: form.max_participants === '' ? null : Number(form.max_participants),
      // A package that meets at the business has no point of its own; the
      // server copies the vendor's.
      latitude: form.uses_vendor_location ? null : Number(form.latitude),
      longitude: form.uses_vendor_location ? null : Number(form.longitude),
    };
    setSaving(true);
    try {
      if (editingId) await apiPut(`/partner/packages/${editingId}`, payload);
      else await apiPost('/partner/packages', payload);
      setModalOpen(false);
      refetch();
    } catch (err) {
      alert(`Could not save: ${err.message}`);
    } finally {
      setSaving(false);
    }
  };

  const remove = async (pkg) => {
    if (!confirm(`Delete "${pkg.title}"? This cannot be undone.`)) return;
    try {
      await apiDelete(`/partner/packages/${pkg.id}`);
      refetch();
    } catch (err) {
      alert(`Could not delete: ${err.message}`);
    }
  };

  return (
    <>
      {error && <div className="login-error">{error}</div>}

      <div className="card" style={{ padding: '24px' }}>
        <div className="card-header">
          <div className="card-title">My packages ({packages.length})</div>
          <button className="btn btn-primary" onClick={openNew}>
            <PlusIcon size={16} /> Add package
          </button>
        </div>

        {loading && <div className="loader" />}

        {!loading && packages.length === 0 && (
          <div className="empty-state">
            <TicketIcon size={32} className="empty-icon" />
            <div>Nothing listed yet. Add your first package to appear in the app.</div>
          </div>
        )}

        {!loading && packages.length > 0 && (
          <div className="modern-list">
            {packages.map((pkg) => (
              <div key={pkg.id} className="modern-list-item">
                <div style={{ flex: 1 }}>
                  <div style={{ fontWeight: 600 }}>{pkg.title}</div>
                  <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                    {pkg.category} {' · '}
                    {pkg.price_amount != null
                      ? `${pkg.price_currency} ${pkg.price_amount}`
                      : 'On request'}
                    {pkg.duration_minutes ? ` · ${pkg.duration_minutes} min` : ''}
                    {!pkg.uses_vendor_location ? ' · own meeting point' : ''}
                  </div>
                </div>
                {/* is_published is the server's word, not the form's: it also
                    depends on whether the whole listing is live. */}
                <span className={`badge ${pkg.is_published ? 'badge-green' : 'badge-yellow'}`}>
                  {pkg.is_published ? 'Live' : 'Hidden'}
                </span>
                <button className="action-icon-btn" title="Edit" onClick={() => openEdit(pkg)}>
                  <EditIcon size={14} />
                </button>
                <button className="action-icon-btn" title="Delete" onClick={() => remove(pkg)}>
                  <TrashIcon size={14} />
                </button>
              </div>
            ))}
          </div>
        )}
      </div>

      {modalOpen && (
        <div className="modal-overlay" onClick={() => setModalOpen(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <form onSubmit={save}>
              <div className="card-header">
                <div className="card-title">{editingId ? 'Edit package' : 'New package'}</div>
              </div>

              <div className="form-group">
                <label className="form-label">Title</label>
                <input
                  type="text" required className="form-input" value={form.title}
                  onChange={(e) => setForm((p) => ({ ...p, title: e.target.value }))}
                />
              </div>

              <div className="form-group">
                <label className="form-label">Short summary (shown on the card)</label>
                <input
                  type="text" maxLength={500} className="form-input" value={form.summary || ''}
                  onChange={(e) => setForm((p) => ({ ...p, summary: e.target.value }))}
                />
              </div>

              <div className="form-group">
                <label className="form-label">Full description</label>
                <textarea
                  className="form-textarea" rows={4} value={form.description || ''}
                  onChange={(e) => setForm((p) => ({ ...p, description: e.target.value }))}
                />
              </div>

              <div className="form-grid-2">
                <div className="form-group">
                  <label className="form-label">Category</label>
                  <select
                    className="form-select" value={form.category || 'other'}
                    onChange={(e) => setForm((p) => ({ ...p, category: e.target.value }))}
                  >
                    {CATEGORIES.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
                  </select>
                </div>
                <div className="form-group">
                  <label className="form-label">Price basis</label>
                  <select
                    className="form-select" value={form.price_basis || 'per_person'}
                    onChange={(e) => setForm((p) => ({ ...p, price_basis: e.target.value }))}
                  >
                    {PRICE_BASES.map((b) => <option key={b.value} value={b.value}>{b.label}</option>)}
                  </select>
                </div>
              </div>

              <div className="form-grid-2">
                <div className="form-group">
                  <label className="form-label">Price (blank = on request)</label>
                  <input
                    type="number" step="0.01" min="0" className="form-input"
                    value={form.price_amount}
                    onChange={(e) => setForm((p) => ({ ...p, price_amount: e.target.value }))}
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">Currency</label>
                  <input
                    type="text" maxLength={10} className="form-input" value={form.price_currency || ''}
                    onChange={(e) => setForm((p) => ({ ...p, price_currency: e.target.value.toUpperCase() }))}
                  />
                </div>
              </div>

              <div className="form-grid-2">
                <div className="form-group">
                  <label className="form-label">Duration (minutes)</label>
                  <input
                    type="number" min="0" className="form-input" value={form.duration_minutes}
                    onChange={(e) => setForm((p) => ({ ...p, duration_minutes: e.target.value }))}
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">Max participants</label>
                  <input
                    type="number" min="1" className="form-input" value={form.max_participants}
                    onChange={(e) => setForm((p) => ({ ...p, max_participants: e.target.value }))}
                  />
                </div>
              </div>

              <div className="form-grid-2">
                <div className="form-group">
                  <label className="form-label">What&rsquo;s included (one per line)</label>
                  <textarea
                    className="form-textarea" rows={3} value={arrayToLines(form.inclusions)}
                    onChange={(e) => setForm((p) => ({ ...p, inclusions: linesToArray(e.target.value) }))}
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">Languages (one per line)</label>
                  <textarea
                    className="form-textarea" rows={3} value={arrayToLines(form.languages)}
                    onChange={(e) => setForm((p) => ({ ...p, languages: linesToArray(e.target.value) }))}
                  />
                </div>
              </div>

              <ImageUploader
                label="Package photos (the first is the card photo)"
                value={form.photo_urls}
                uploadEndpoint="/partner/upload"
                onChange={(urls) => setForm((p) => ({ ...p, photo_urls: urls }))}
              />

              <div className="form-group">
                <label className="form-label" style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <input
                    type="checkbox"
                    checked={!form.uses_vendor_location}
                    onChange={(e) => setForm((p) => ({
                      ...p,
                      uses_vendor_location: !e.target.checked,
                      latitude: e.target.checked ? '' : null,
                      longitude: e.target.checked ? '' : null,
                    }))}
                  />
                  This package meets somewhere other than my business address
                </label>
              </div>

              {!form.uses_vendor_location && (
                <LocationPicker
                  mapId="partner-package-map"
                  latitude={form.latitude ?? ''}
                  longitude={form.longitude ?? ''}
                  address={form.meeting_point_address || ''}
                  searchEndpoint="/partner/place-search"
                  onPick={(p) => {
                    const next = { ...p };
                    delete next.name;
                    delete next.google_place_id;
                    const picked = next.address;
                    delete next.address;
                    setForm((prev) => ({
                      ...prev, ...next,
                      ...(picked !== undefined ? { meeting_point_address: picked } : {}),
                    }));
                  }}
                />
              )}

              <div className="form-group">
                <label className="form-label">Show in the app</label>
                <select
                  className="form-select" value={form.is_active ? 'yes' : 'no'}
                  onChange={(e) => setForm((p) => ({ ...p, is_active: e.target.value === 'yes' }))}
                >
                  <option value="yes">Yes</option>
                  <option value="no">No &mdash; keep it hidden</option>
                </select>
              </div>

              <div style={{ display: 'flex', gap: '10px', marginTop: '8px' }}>
                <button type="submit" className="btn btn-primary" disabled={saving}>
                  {saving ? 'Saving…' : editingId ? 'Save package' : 'Create package'}
                </button>
                <button type="button" className="btn btn-ghost" onClick={() => setModalOpen(false)}>
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </>
  );
}
