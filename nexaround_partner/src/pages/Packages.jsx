import { useState } from 'react';
import { useApi, apiPost, apiPut, apiDelete, mediaUrl } from '../api';
import { RESYNC, useLiveEvent } from '../live';
import {
  PlusIcon, TrashIcon, TicketIcon, SearchIcon, DollarIcon, ImageIcon, ClipboardCheckIcon, MapPinIcon,
} from '../components/Icons';
import { Switch, Drawer, Toast, Section } from '../components/Kit';
import LocationPicker from '../components/LocationPicker';
import ImageUploader from '../components/ImageUploader';
import {
  CATEGORIES, PRICE_BASES, categoryLabel, categoryTone, basisLabel, formatPrice, formatDuration,
  visibility, visibilityTone,
} from '../format';

const empty = {
  title: '', summary: '', description: '', category: 'boat', tags: [],
  photo_urls: [], price_amount: '', price_currency: 'LKR',
  price_basis: 'per_person', duration_minutes: '', max_participants: '',
  inclusions: [], languages: [], uses_vendor_location: true,
  meeting_point_address: '', is_active: true, latitude: null, longitude: null,
};

const linesToArray = (t) => t.split('\n').map((l) => l.trim()).filter(Boolean);
const arrayToLines = (a) => (a || []).join('\n');

// A package that meets at the business has no point of its own; the server
// copies the vendor's.
const toPayload = (form) => ({
  ...form,
  price_amount: form.price_amount === '' || form.price_amount == null ? null : Number(form.price_amount),
  duration_minutes: form.duration_minutes === '' || form.duration_minutes == null ? null : Number(form.duration_minutes),
  max_participants: form.max_participants === '' || form.max_participants == null ? null : Number(form.max_participants),
  latitude: form.uses_vendor_location ? null : Number(form.latitude),
  longitude: form.uses_vendor_location ? null : Number(form.longitude),
});

export default function Packages({ initialTarget }) {
  const { data, error, refetch } = useApi('/partner/packages');
  const [packages, setPackages] = useState(null); // optimistic copy of data
  const list = packages ?? data?.packages ?? [];

  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [form, setForm] = useState(empty);
  const [saving, setSaving] = useState(false);
  const [toast, setToast] = useState(null);

  const notify = (message, tone = 'ok') => {
    setToast({ message, tone });
    setTimeout(() => setToast(null), 3500);
  };

  const reload = () => {
    setPackages(null);
    refetch();
  };

  // Changed elsewhere (another tab, another login, or NexAround). The
  // optimistic copy is dropped only once the fresh list has landed, so a
  // switch just flipped here does not blink back while the refetch is out.
  const [staleData, setStaleData] = useState(null);
  if (staleData && data !== staleData) {
    setStaleData(null);
    setPackages(null);
  }
  useLiveEvent(['packages.changed', 'account.changed', RESYNC], () => {
    setStaleData(data || {});
    refetch();
  });

  const patch = (p) => setForm((prev) => ({ ...prev, ...p }));

  const openNew = () => { setEditingId(null); setForm(empty); setDrawerOpen(true); };
  const openEdit = (pkg) => {
    setEditingId(pkg.id);
    setForm({
      ...empty, ...pkg,
      price_amount: pkg.price_amount ?? '',
      duration_minutes: pkg.duration_minutes ?? '',
      max_participants: pkg.max_participants ?? '',
      summary: pkg.summary || '',
      description: pkg.description || '',
    });
    setDrawerOpen(true);
  };

  // Opened from the dashboard: 'new' opens a blank form, a package id opens
  // that package once the list has loaded.
  const [pendingTarget, setPendingTarget] = useState(initialTarget || null);
  if (pendingTarget === 'new') {
    setPendingTarget(null);
    openNew();
  } else if (pendingTarget && data) {
    const match = data.packages.find((p) => p.id === pendingTarget);
    setPendingTarget(null);
    if (match) openEdit(match);
  }

  const save = async (e) => {
    e.preventDefault();
    if (!form.uses_vendor_location && (form.latitude === '' || form.latitude == null)) {
      notify('Pick the meeting point on the map, or use your business address.', 'error');
      return;
    }
    setSaving(true);
    try {
      if (editingId) await apiPut(`/partner/packages/${editingId}`, toPayload(form));
      else await apiPost('/partner/packages', toPayload(form));
      setDrawerOpen(false);
      reload();
      notify(editingId ? 'Package saved' : 'Package created');
    } catch (err) {
      notify(`Could not save: ${err.message}`, 'error');
    } finally {
      setSaving(false);
    }
  };

  const remove = async (pkg) => {
    if (!confirm(`Delete "${pkg.title}"? This cannot be undone.`)) return;
    try {
      await apiDelete(`/partner/packages/${pkg.id}`);
      setDrawerOpen(false);
      reload();
      notify('Package deleted');
    } catch (err) {
      notify(`Could not delete: ${err.message}`, 'error');
    }
  };

  const toggleLive = async (pkg, isActive) => {
    // Optimistic, so the switch moves under the cursor.
    setPackages(list.map((p) => (p.id === pkg.id ? { ...p, is_active: isActive } : p)));
    try {
      const updated = await apiPut(`/partner/packages/${pkg.id}`, toPayload({ ...pkg, is_active: isActive }));
      setPackages((prev) => (prev || list).map((p) => (p.id === pkg.id ? updated : p)));
    } catch (err) {
      setPackages((prev) => (prev || list).map((p) => (p.id === pkg.id ? { ...p, is_active: !isActive } : p)));
      notify(`Could not update: ${err.message}`, 'error');
    }
  };

  const liveCount = list.filter((p) => p.is_active).length;
  const q = search.trim().toLowerCase();
  const filtered = list.filter((p) =>
    (statusFilter === 'all' || (statusFilter === 'live' ? p.is_active : !p.is_active))
    && (!q || [p.title, p.summary, categoryLabel(p.category)].some((f) => (f || '').toLowerCase().includes(q)))
  );

  const filters = [
    ['all', 'All', list.length],
    ['live', 'Live', liveCount],
    ['hidden', 'Hidden', list.length - liveCount],
  ];

  return (
    <>
      <div className="xp-toolbar">
        <div className="seg">
          {filters.map(([value, label, count]) => (
            <button
              key={value}
              className={`seg-btn ${statusFilter === value ? 'active' : ''}`}
              onClick={() => setStatusFilter(value)}
            >
              {label} <span className="seg-count">{count}</span>
            </button>
          ))}
        </div>
        <div className="xp-toolbar-right">
          <div className="search-bar">
            <SearchIcon size={16} />
            <input type="text" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search your packages…" />
          </div>
          <button className="btn btn-primary btn-sm" onClick={openNew}>
            <PlusIcon size={15} /> Add package
          </button>
        </div>
      </div>

      {error && <div className="login-error">{error}</div>}

      {!data && !error && <div className="loader" />}

      {data && list.length === 0 && (
        <div className="card xp-empty" style={{ padding: 56 }}>
          <TicketIcon size={36} />
          <strong>List your first package</strong>
          Each package appears in the app as its own experience travellers can enquire about.
          <div style={{ marginTop: 14 }}>
            <button className="btn btn-primary btn-sm" onClick={openNew}>
              <PlusIcon size={15} /> Add package
            </button>
          </div>
        </div>
      )}

      {data && list.length > 0 && filtered.length === 0 && (
        <div className="card xp-empty" style={{ padding: 48 }}>
          <strong>Nothing matches</strong>
          Try a different search or status.
        </div>
      )}

      {filtered.length > 0 && (
        <div className="pkg-grid">
          {filtered.map((pkg) => (
            <div
              key={pkg.id}
              className={`pkg-card ${pkg.is_published ? '' : 'is-hidden'}`}
              onClick={() => openEdit(pkg)}
            >
              <div className="pkg-card-img">
                {pkg.photo_urls?.[0] ? <img src={mediaUrl(pkg.photo_urls[0])} alt="" /> : <TicketIcon size={28} />}
                <span className={`pill tone-${visibilityTone(pkg)}`}>{visibility(pkg)}</span>
              </div>
              <div className="pkg-card-body">
                <div className={`pkg-eyebrow tone-${categoryTone(pkg.category)}`}>{categoryLabel(pkg.category)}</div>
                <div className="pkg-card-title">{pkg.title}</div>
                {pkg.summary && <div className="pkg-card-vendor">{pkg.summary}</div>}
                <div className="pkg-card-foot">
                  <div>
                    <div className="pkg-price">{formatPrice(pkg)}</div>
                    <div className="sub">
                      {basisLabel(pkg.price_basis)}
                      {pkg.duration_minutes ? ` · ${formatDuration(pkg.duration_minutes)}` : ''}
                    </div>
                  </div>
                  <Switch checked={pkg.is_active} onChange={(v) => toggleLive(pkg, v)} label="Show in app" />
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {drawerOpen && (
        <Drawer
          title={editingId ? 'Edit package' : 'New package'}
          subtitle={editingId ? undefined : 'Only the title is required. You can fill in the rest later.'}
          onClose={() => setDrawerOpen(false)}
          onSubmit={save}
          footer={
            <>
              <Switch
                checked={form.is_active}
                onChange={(v) => patch({ is_active: v })}
                label={form.is_active ? 'Show in the app' : 'Hidden (draft)'}
              />
              <div className="drawer-foot-actions">
                {editingId && (
                  <button type="button" className="icon-btn danger" title="Delete package" onClick={() => remove({ ...form, id: editingId })}>
                    <TrashIcon size={15} />
                  </button>
                )}
                <button type="button" className="btn btn-ghost btn-sm" onClick={() => setDrawerOpen(false)}>Cancel</button>
                <button type="submit" className="btn btn-primary btn-sm" disabled={saving}>
                  {saving ? 'Saving…' : editingId ? 'Save package' : 'Create package'}
                </button>
              </div>
            </>
          }
        >
          <Section tone="teal" icon={TicketIcon} title="Basic details" hint="What travellers see first.">
            <div className="form-group">
              <label className="form-label">Title *</label>
              <input
                type="text" required autoFocus className="form-input" value={form.title}
                placeholder="Pigeon Island snorkelling & boat safari"
                onChange={(e) => patch({ title: e.target.value })}
              />
            </div>
            <div className="form-group">
              <label className="form-label">Category</label>
              <select className="form-select" value={form.category || 'other'} onChange={(e) => patch({ category: e.target.value })}>
                {CATEGORIES.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label className="form-label">Summary</label>
              <input
                type="text" maxLength={500} className="form-input" value={form.summary}
                placeholder="One line for the card in the app"
                onChange={(e) => patch({ summary: e.target.value })}
              />
            </div>
            <div className="form-group">
              <label className="form-label">Description</label>
              <textarea
                className="form-textarea" rows={4} value={form.description}
                placeholder="Itinerary, what to bring, safety notes…"
                onChange={(e) => patch({ description: e.target.value })}
              />
            </div>
          </Section>

          <Section tone="amber" icon={DollarIcon} title="Price & capacity" hint="Leave the price empty to show “On request”.">
            <div className="form-grid-3">
              <div className="form-group">
                <label className="form-label">Price</label>
                <input
                  type="number" step="0.01" min="0" className="form-input" placeholder="7500"
                  value={form.price_amount} onChange={(e) => patch({ price_amount: e.target.value })}
                />
              </div>
              <div className="form-group">
                <label className="form-label">Currency</label>
                <input
                  type="text" maxLength={10} className="form-input" value={form.price_currency || ''}
                  onChange={(e) => patch({ price_currency: e.target.value.toUpperCase() })}
                />
              </div>
              <div className="form-group">
                <label className="form-label">Basis</label>
                <select className="form-select" value={form.price_basis || 'per_person'} onChange={(e) => patch({ price_basis: e.target.value })}>
                  {PRICE_BASES.map((b) => <option key={b.value} value={b.value}>{b.label}</option>)}
                </select>
              </div>
            </div>
            <div className="form-grid-2">
              <div className="form-group">
                <label className="form-label">Duration (minutes)</label>
                <input
                  type="number" min="0" className="form-input" placeholder="180"
                  value={form.duration_minutes} onChange={(e) => patch({ duration_minutes: e.target.value })}
                />
              </div>
              <div className="form-group">
                <label className="form-label">Max participants</label>
                <input
                  type="number" min="1" className="form-input" placeholder="8"
                  value={form.max_participants} onChange={(e) => patch({ max_participants: e.target.value })}
                />
              </div>
            </div>
          </Section>

          <Section tone="violet" icon={ImageIcon} title="Photos" hint="The first photo is the one shown on the card.">
            <ImageUploader
              label={null}
              value={form.photo_urls}
              uploadEndpoint="/partner/upload"
              onChange={(urls) => patch({ photo_urls: urls })}
            />
          </Section>

          <Section tone="blue" icon={ClipboardCheckIcon} title="Included & languages" hint="One item per line.">
            <div className="form-grid-2">
              <div className="form-group">
                <label className="form-label">What&rsquo;s included</label>
                <textarea
                  className="form-textarea" rows={4} value={arrayToLines(form.inclusions)}
                  placeholder={'Snorkelling gear\nLife jackets\nBottled water'}
                  onChange={(e) => patch({ inclusions: linesToArray(e.target.value) })}
                />
              </div>
              <div className="form-group">
                <label className="form-label">Languages</label>
                <textarea
                  className="form-textarea" rows={4} value={arrayToLines(form.languages)}
                  placeholder={'English\nTamil\nSinhala'}
                  onChange={(e) => patch({ languages: linesToArray(e.target.value) })}
                />
              </div>
            </div>
          </Section>

          <Section
            tone="rose"
            icon={MapPinIcon}
            title="Meeting point"
            hint="Where travellers meet you."
            action={
              <Switch
                checked={form.uses_vendor_location}
                onChange={(v) => patch({ uses_vendor_location: v, latitude: v ? null : '', longitude: v ? null : '' })}
                label="My business address"
              />
            }
          >
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
          </Section>
        </Drawer>
      )}

      <Toast toast={toast} />
    </>
  );
}
