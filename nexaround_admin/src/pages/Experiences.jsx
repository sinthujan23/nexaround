import { useEffect, useState } from 'react';
import { useApi, apiGet, apiPost, apiPut, apiPatch, apiDelete } from '../api';
import {
  PlusIcon, EditIcon, TrashIcon, SearchIcon, RefreshIcon, EyeOffIcon,
} from '../components/Icons';
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

const emptyVendor = {
  name: '', description: '', latitude: '', longitude: '', address: '',
  google_place_id: '', city: '', country_code: '', contact_phone: '',
  contact_whatsapp: '', contact_instagram: '', contact_facebook: '',
  contact_x: '', contact_email: '', website: '', logo_url: '',
  photo_urls: [], rating: '', review_count: 0, internal_notes: '',
  is_active: true, sort_order: 0,
};

const emptyPackage = {
  title: '', summary: '', description: '', category: 'boat', tags: [],
  photo_urls: [], price_amount: '', price_currency: 'LKR',
  price_basis: 'per_person', duration_minutes: '', max_participants: '',
  inclusions: [], languages: [], uses_vendor_location: true,
  latitude: null, longitude: null, meeting_point_address: '',
  is_active: true, sort_order: 0,
};

// Multi-line textareas edit array columns; one entry per line.
const linesToArray = (text) =>
  text.split('\n').map((line) => line.trim()).filter(Boolean);
const arrayToLines = (arr) => (arr || []).join('\n');

export default function Experiences() {
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [selected, setSelected] = useState(null);
  const [form, setForm] = useState(emptyVendor);
  const [saving, setSaving] = useState(false);

  const [packages, setPackages] = useState([]);
  const [packagesLoading, setPackagesLoading] = useState(false);
  const [logins, setLogins] = useState([]);
  const [loginModalOpen, setLoginModalOpen] = useState(false);
  const [loginForm, setLoginForm] = useState({ email: '', display_name: '' });
  const [loginBusy, setLoginBusy] = useState(false);
  const [packageModalOpen, setPackageModalOpen] = useState(false);
  const [packageForm, setPackageForm] = useState(emptyPackage);
  const [editingPackageId, setEditingPackageId] = useState(null);

  useEffect(() => {
    const handle = setTimeout(() => setDebouncedSearch(search), 400);
    return () => clearTimeout(handle);
  }, [search]);

  const { data, loading, error, refetch } = useApi(
    `/admin/experiences/vendors?search=${encodeURIComponent(debouncedSearch)}&page=1&page_size=100`
  );
  const vendors = data?.vendors || [];

  // The vendor's partner-portal accounts. Loaded beside the packages because
  // a vendor can have logins and no packages, or the reverse.
  const loadLogins = async (vendorId) => {
    try {
      const res = await apiGet(`/admin/experiences/vendors/${vendorId}/logins`);
      setLogins(res.logins || []);
    } catch {
      setLogins([]);
    }
  };

  const createLogin = async (e) => {
    e.preventDefault();
    setLoginBusy(true);
    try {
      await apiPost(`/admin/experiences/vendors/${selected.id}/logins`, loginForm);
      setLoginModalOpen(false);
      setLoginForm({ email: '', display_name: '' });
      loadLogins(selected.id);
    } catch (err) {
      alert(`Could not create the login: ${err.message}`);
    } finally {
      setLoginBusy(false);
    }
  };

  const resendInvite = async (login) => {
    try {
      await apiPost(`/admin/experiences/logins/${login.id}/resend-invite`, {});
      alert(`A new link has been emailed to ${login.email}. Any earlier link stops working.`);
    } catch (err) {
      alert(`Could not send the link: ${err.message}`);
    }
  };

  const toggleLogin = async (login) => {
    try {
      await apiPatch(`/admin/experiences/logins/${login.id}`, { is_active: !login.is_active });
      loadLogins(selected.id);
    } catch (err) {
      alert(`Could not update the login: ${err.message}`);
    }
  };

  const deleteLogin = async (login) => {
    if (!confirm(`Remove the login for ${login.email}? They lose access immediately.`)) return;
    try {
      await apiDelete(`/admin/experiences/logins/${login.id}`);
      loadLogins(selected.id);
    } catch (err) {
      alert(`Could not remove the login: ${err.message}`);
    }
  };

  const loadPackages = async (vendorId) => {
    setPackagesLoading(true);
    try {
      const res = await apiGet(`/admin/experiences/vendors/${vendorId}/packages`);
      setPackages(res.packages || []);
    } catch (err) {
      alert(`Could not load packages: ${err.message}`);
      setPackages([]);
    } finally {
      setPackagesLoading(false);
    }
  };

  const selectVendor = (vendor) => {
    setSelected(vendor);
    setForm({
      ...emptyVendor,
      ...vendor,
      rating: vendor.rating ?? '',
      description: vendor.description || '',
      photo_urls: vendor.photo_urls || [],
    });
    loadPackages(vendor.id);
    loadLogins(vendor.id);
  };

  const startNewVendor = () => {
    setSelected(null);
    setForm(emptyVendor);
    setPackages([]);
    setLogins([]);
  };

  const patchForm = (patch) => setForm((prev) => ({ ...prev, ...patch }));

  const saveVendor = async (e) => {
    e.preventDefault();
    if (form.latitude === '' || form.longitude === '') {
      alert('Please set the vendor location on the map first.');
      return;
    }

    const payload = {
      ...form,
      latitude: Number(form.latitude),
      longitude: Number(form.longitude),
      rating: form.rating === '' ? null : Number(form.rating),
      review_count: Number(form.review_count) || 0,
      sort_order: Number(form.sort_order) || 0,
    };

    setSaving(true);
    try {
      if (selected) {
        const updated = await apiPut(`/admin/experiences/vendors/${selected.id}`, payload);
        setSelected(updated);
        // The vendor's coordinates and active flag cascade to its packages
        // server-side, so the list we are showing is now stale.
        loadPackages(updated.id);
      } else {
        const created = await apiPost('/admin/experiences/vendors', payload);
        setSelected(created);
        setForm({ ...emptyVendor, ...created, rating: created.rating ?? '' });
      }
      refetch();
    } catch (err) {
      alert(`Failed to save vendor: ${err.message}`);
    } finally {
      setSaving(false);
    }
  };

  const deleteVendor = async () => {
    if (!selected) return;
    if (!confirm(`Delete "${selected.name}" and all of its packages? This cannot be undone.`)) return;
    try {
      await apiDelete(`/admin/experiences/vendors/${selected.id}`);
      startNewVendor();
      refetch();
    } catch (err) {
      alert(`Failed to delete vendor: ${err.message}`);
    }
  };

  const openNewPackage = () => {
    setEditingPackageId(null);
    setPackageForm(emptyPackage);
    setPackageModalOpen(true);
  };

  const openEditPackage = (pkg) => {
    setEditingPackageId(pkg.id);
    setPackageForm({
      ...emptyPackage,
      ...pkg,
      price_amount: pkg.price_amount ?? '',
      duration_minutes: pkg.duration_minutes ?? '',
      max_participants: pkg.max_participants ?? '',
      summary: pkg.summary || '',
      description: pkg.description || '',
    });
    setPackageModalOpen(true);
  };

  const savePackage = async (e) => {
    e.preventDefault();
    if (!selected) return;

    const payload = {
      ...packageForm,
      price_amount: packageForm.price_amount === '' ? null : Number(packageForm.price_amount),
      duration_minutes: packageForm.duration_minutes === '' ? null : Number(packageForm.duration_minutes),
      max_participants: packageForm.max_participants === '' ? null : Number(packageForm.max_participants),
      sort_order: Number(packageForm.sort_order) || 0,
      latitude: packageForm.uses_vendor_location ? null : Number(packageForm.latitude),
      longitude: packageForm.uses_vendor_location ? null : Number(packageForm.longitude),
    };

    try {
      if (editingPackageId) {
        await apiPut(`/admin/experiences/packages/${editingPackageId}`, payload);
      } else {
        await apiPost(`/admin/experiences/vendors/${selected.id}/packages`, payload);
      }
      setPackageModalOpen(false);
      loadPackages(selected.id);
      refetch();
    } catch (err) {
      alert(`Failed to save package: ${err.message}`);
    }
  };

  const deletePackage = async (pkg) => {
    if (!confirm(`Delete "${pkg.title}"?`)) return;
    try {
      await apiDelete(`/admin/experiences/packages/${pkg.id}`);
      loadPackages(selected.id);
      refetch();
    } catch (err) {
      alert(`Failed to delete package: ${err.message}`);
    }
  };

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px', gap: '12px' }}>
        <div className="search-bar" style={{ flex: 1, maxWidth: '420px' }}>
          <SearchIcon size={18} />
          <input
            type="text"
            placeholder="Search vendors…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <button className="btn btn-primary" onClick={startNewVendor}>
          <PlusIcon size={16} /> New Vendor
        </button>
      </div>

      {error && <div className="login-error">{error}</div>}

      <div className="approvals-split">
        <div className="approvals-list-col">
          <div className="card">
            <div className="card-header">
              <div className="card-title">Vendors {data ? `(${data.total})` : ''}</div>
            </div>

            {loading && <div className="loader" />}

            {!loading && vendors.length === 0 && (
              <div className="empty-state">
                <div>No vendors yet. Create the first one to get started.</div>
              </div>
            )}

            {!loading && vendors.length > 0 && (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>Name</th>
                      <th>Location</th>
                      <th>Packages</th>
                      <th>Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {vendors.map((vendor) => (
                      <tr
                        key={vendor.id}
                        className={`clickable-row ${selected?.id === vendor.id ? 'selected' : ''}`}
                        onClick={() => selectVendor(vendor)}
                      >
                        <td><strong>{vendor.name}</strong></td>
                        <td style={{ color: 'var(--text-secondary)' }}>
                          {vendor.city || vendor.address || '—'}
                        </td>
                        <td>{vendor.package_count}</td>
                        <td>
                          <span className={`badge ${vendor.is_active ? 'badge-green' : 'badge-red'}`}>
                            {vendor.is_active ? 'Active' : 'Hidden'}
                          </span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </div>

        <div className="approvals-map-col">
          <form className="card" style={{ padding: '24px' }} onSubmit={saveVendor}>
            <div className="card-header">
              <div className="card-title">{selected ? `Edit: ${selected.name}` : 'New vendor'}</div>
            </div>

            <div className="form-group">
              <label className="form-label">Vendor name</label>
              <input
                type="text" required className="form-input" value={form.name}
                onChange={(e) => patchForm({ name: e.target.value })}
              />
            </div>

            <div className="form-group">
              <label className="form-label">Description</label>
              <textarea
                className="form-textarea" rows={3} value={form.description}
                onChange={(e) => patchForm({ description: e.target.value })}
              />
            </div>

            <LocationPicker
              mapId="vendor-location-map"
              latitude={form.latitude}
              longitude={form.longitude}
              address={form.address}
              onPick={(patch) => {
                // A Google result may suggest a name, but never clobber one the
                // admin has already typed.
                const next = { ...patch };
                if (next.name !== undefined && form.name) delete next.name;
                patchForm(next);
              }}
            />

            <div className="form-grid-2">
              <div className="form-group">
                <label className="form-label">City</label>
                <input
                  type="text" className="form-input" value={form.city || ''}
                  onChange={(e) => patchForm({ city: e.target.value })}
                />
              </div>
              <div className="form-group">
                <label className="form-label">Country code (2 letters)</label>
                <input
                  type="text" maxLength={2} className="form-input"
                  value={form.country_code || ''}
                  onChange={(e) => patchForm({ country_code: e.target.value.toUpperCase() })}
                />
              </div>
            </div>

            <div className="form-grid-2">
              <div className="form-group">
                <label className="form-label">Phone</label>
                <input
                  type="text" className="form-input" value={form.contact_phone || ''}
                  onChange={(e) => patchForm({ contact_phone: e.target.value })}
                />
              </div>
              <div className="form-group">
                <label className="form-label">WhatsApp</label>
                <input
                  type="text" className="form-input" value={form.contact_whatsapp || ''}
                  onChange={(e) => patchForm({ contact_whatsapp: e.target.value })}
                />
              </div>
            </div>

            <div className="form-grid-2">
              <div className="form-group">
                <label className="form-label">Email (for enquiries — not shown in the app)</label>
                <input
                  type="email" className="form-input" value={form.contact_email || ''}
                  onChange={(e) => patchForm({ contact_email: e.target.value })}
                />
              </div>
              <div className="form-group">
                <label className="form-label">Website</label>
                <input
                  type="text" className="form-input" value={form.website || ''}
                  onChange={(e) => patchForm({ website: e.target.value })}
                />
              </div>
            </div>

            <div className="form-grid-3" style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '16px', marginBottom: '16px' }}>
              <div className="form-group">
                <label className="form-label">Instagram (@handle or link)</label>
                <input
                  type="text" className="form-input" placeholder="@trinco_boat or https://..."
                  value={form.contact_instagram || ''}
                  onChange={(e) => patchForm({ contact_instagram: e.target.value })}
                />
              </div>
              <div className="form-group">
                <label className="form-label">Facebook (link or page)</label>
                <input
                  type="text" className="form-input" placeholder="facebook.com/... or page name"
                  value={form.contact_facebook || ''}
                  onChange={(e) => patchForm({ contact_facebook: e.target.value })}
                />
              </div>
              <div className="form-group">
                <label className="form-label">X / Twitter (@handle or link)</label>
                <input
                  type="text" className="form-input" placeholder="@trinco_boat or https://..."
                  value={form.contact_x || ''}
                  onChange={(e) => patchForm({ contact_x: e.target.value })}
                />
              </div>
            </div>

            <ImageUploader
              label="Vendor photos"
              value={form.photo_urls}
              onChange={(urls) => patchForm({ photo_urls: urls })}
            />

            <div className="form-grid-2">
              <div className="form-group">
                <label className="form-label">Rating (0–5, optional)</label>
                <input
                  type="number" step="0.1" min="0" max="5" className="form-input"
                  value={form.rating}
                  onChange={(e) => patchForm({ rating: e.target.value })}
                />
              </div>
              <div className="form-group">
                <label className="form-label">Status</label>
                <select
                  className="form-select"
                  value={form.is_active ? 'active' : 'hidden'}
                  onChange={(e) => patchForm({ is_active: e.target.value === 'active' })}
                >
                  <option value="active">Active</option>
                  <option value="hidden">Hidden</option>
                </select>
              </div>
            </div>

            <div className="form-group">
              <label className="form-label">Internal notes (admin only)</label>
              <textarea
                className="form-textarea" rows={2} value={form.internal_notes || ''}
                onChange={(e) => patchForm({ internal_notes: e.target.value })}
              />
            </div>

            <div style={{ display: 'flex', gap: '10px' }}>
              <button type="submit" className="btn btn-primary" disabled={saving}>
                {saving ? 'Saving…' : selected ? 'Save changes' : 'Create vendor'}
              </button>
              {selected && (
                <button type="button" className="btn btn-ghost" onClick={deleteVendor}>
                  <TrashIcon size={16} /> Delete
                </button>
              )}
            </div>
          </form>

          {selected && (
            <div className="card" style={{ padding: '24px', marginTop: '20px' }}>
              <div className="card-header">
                <div className="card-title">Packages ({packages.length})</div>
                <button className="btn btn-primary" onClick={openNewPackage}>
                  <PlusIcon size={16} /> Add package
                </button>
              </div>

              {packagesLoading && <div className="loader" />}

              {!packagesLoading && packages.length === 0 && (
                <div className="empty-state">
                  <div>No packages yet. Each package becomes its own card in the app.</div>
                </div>
              )}

              {!packagesLoading && packages.length > 0 && (
                <div className="modern-list">
                  {packages.map((pkg) => (
                    <div key={pkg.id} className="modern-list-item">
                      <div style={{ flex: 1 }}>
                        <div style={{ fontWeight: 600 }}>{pkg.title}</div>
                        <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                          {pkg.category} ·{' '}
                          {pkg.price_amount != null
                            ? `${pkg.price_currency} ${pkg.price_amount}`
                            : 'On request'}
                          {pkg.duration_minutes ? ` · ${pkg.duration_minutes} min` : ''}
                          {!pkg.uses_vendor_location ? ' · own meeting point' : ''}
                        </div>
                      </div>
                      <span className={`badge ${pkg.is_published ? 'badge-green' : 'badge-yellow'}`}>
                        {pkg.is_published ? 'Live' : 'Hidden'}
                      </span>
                      <button
                        className="action-icon-btn" title="Edit"
                        onClick={() => openEditPackage(pkg)}
                      >
                        <EditIcon size={14} />
                      </button>
                      <button
                        className="action-icon-btn" title="Delete"
                        onClick={() => deletePackage(pkg)}
                      >
                        <TrashIcon size={14} />
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {selected && (
            <div className="card" style={{ padding: '24px', marginTop: '20px' }}>
              <div className="card-header">
                <div className="card-title">Portal logins ({logins.length})</div>
                <button className="btn btn-primary" onClick={() => setLoginModalOpen(true)}>
                  <PlusIcon size={16} /> Add login
                </button>
              </div>

              <div style={{ fontSize: '12px', color: 'var(--text-secondary)', marginBottom: '12px' }}>
                Who can sign in at partner.nexaround.com to manage this vendor. They set
                their own password from the emailed link &mdash; you never see it.
              </div>

              {logins.length === 0 && (
                <div className="empty-state">
                  <div>No logins yet. Add one to give this vendor access.</div>
                </div>
              )}

              {logins.length > 0 && (
                <div className="table-wrap">
                  <table>
                    <thead>
                      <tr>
                        <th>Email</th>
                        <th>Name</th>
                        <th>Status</th>
                        <th>Last sign-in</th>
                        <th></th>
                      </tr>
                    </thead>
                    <tbody>
                      {logins.map((l) => (
                        <tr key={l.id}>
                          <td>{l.email}</td>
                          <td>{l.display_name || '—'}</td>
                          <td>
                            {!l.is_active ? (
                              <span className="badge badge-ghost">Disabled</span>
                            ) : l.has_password ? (
                              <span className="badge badge-green">Active</span>
                            ) : (
                              <span className="badge badge-yellow">Invite pending</span>
                            )}
                          </td>
                          <td>
                            {l.last_login_at
                              ? new Date(l.last_login_at).toLocaleString('en-GB', {
                                  timeZone: 'Asia/Colombo',
                                  dateStyle: 'medium',
                                  timeStyle: 'short',
                                })
                              : 'Never'}
                          </td>
                          <td style={{ textAlign: 'right', whiteSpace: 'nowrap' }}>
                            <button
                              className="action-icon-btn"
                              title={l.has_password ? 'Send a password reset link' : 'Resend the invite'}
                              onClick={() => resendInvite(l)}
                            >
                              <RefreshIcon size={14} />
                            </button>
                            <button
                              className="action-icon-btn"
                              title={l.is_active ? 'Disable this login' : 'Enable this login'}
                              onClick={() => toggleLogin(l)}
                            >
                              <EyeOffIcon size={14} />
                            </button>
                            <button
                              className="action-icon-btn" title="Remove"
                              onClick={() => deleteLogin(l)}
                            >
                              <TrashIcon size={14} />
                            </button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          )}
        </div>
      </div>

      {loginModalOpen && (
        <div className="modal-overlay" onClick={() => setLoginModalOpen(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <form onSubmit={createLogin}>
              <div className="card-header">
                <div className="card-title">Add a portal login</div>
              </div>
              <div className="form-group">
                <label className="form-label">Email</label>
                <input
                  type="email" required className="form-input"
                  placeholder="owner@theiragency.com"
                  value={loginForm.email}
                  onChange={(e) => setLoginForm((p) => ({ ...p, email: e.target.value }))}
                />
              </div>
              <div className="form-group">
                <label className="form-label">Name (optional)</label>
                <input
                  type="text" className="form-input"
                  value={loginForm.display_name}
                  onChange={(e) => setLoginForm((p) => ({ ...p, display_name: e.target.value }))}
                />
              </div>
              <div style={{ fontSize: '12px', color: 'var(--text-secondary)', marginBottom: '12px' }}>
                They will be emailed a link to set their own password, valid for 3 days.
              </div>
              <div style={{ display: 'flex', gap: '10px', marginTop: '8px' }}>
                <button type="submit" className="btn btn-primary" disabled={loginBusy}>
                  {loginBusy ? 'Sending…' : 'Create and send invite'}
                </button>
                <button type="button" className="btn btn-ghost" onClick={() => setLoginModalOpen(false)}>
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {packageModalOpen && (
        <div className="modal-overlay" onClick={() => setPackageModalOpen(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <form onSubmit={savePackage}>
              <div className="card-header">
                <div className="card-title">
                  {editingPackageId ? 'Edit package' : 'New package'}
                </div>
              </div>

              <div className="form-group">
                <label className="form-label">Title</label>
                <input
                  type="text" required className="form-input" value={packageForm.title}
                  onChange={(e) => setPackageForm((p) => ({ ...p, title: e.target.value }))}
                />
              </div>

              <div className="form-group">
                <label className="form-label">Short summary (shown on the card)</label>
                <input
                  type="text" maxLength={500} className="form-input" value={packageForm.summary}
                  onChange={(e) => setPackageForm((p) => ({ ...p, summary: e.target.value }))}
                />
              </div>

              <div className="form-group">
                <label className="form-label">Full description</label>
                <textarea
                  className="form-textarea" rows={4} value={packageForm.description}
                  onChange={(e) => setPackageForm((p) => ({ ...p, description: e.target.value }))}
                />
              </div>

              <div className="form-grid-2">
                <div className="form-group">
                  <label className="form-label">Category</label>
                  <select
                    className="form-select" value={packageForm.category}
                    onChange={(e) => setPackageForm((p) => ({ ...p, category: e.target.value }))}
                  >
                    {CATEGORIES.map((c) => (
                      <option key={c.value} value={c.value}>{c.label}</option>
                    ))}
                  </select>
                </div>
                <div className="form-group">
                  <label className="form-label">Price basis</label>
                  <select
                    className="form-select" value={packageForm.price_basis}
                    onChange={(e) => setPackageForm((p) => ({ ...p, price_basis: e.target.value }))}
                  >
                    {PRICE_BASES.map((b) => (
                      <option key={b.value} value={b.value}>{b.label}</option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="form-grid-2">
                <div className="form-group">
                  <label className="form-label">Price (blank = on request)</label>
                  <input
                    type="number" step="0.01" min="0" className="form-input"
                    value={packageForm.price_amount}
                    onChange={(e) => setPackageForm((p) => ({ ...p, price_amount: e.target.value }))}
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">Currency</label>
                  <input
                    type="text" maxLength={10} className="form-input"
                    value={packageForm.price_currency}
                    onChange={(e) => setPackageForm((p) => ({ ...p, price_currency: e.target.value.toUpperCase() }))}
                  />
                </div>
              </div>

              <div className="form-grid-2">
                <div className="form-group">
                  <label className="form-label">Duration (minutes)</label>
                  <input
                    type="number" min="0" className="form-input"
                    value={packageForm.duration_minutes}
                    onChange={(e) => setPackageForm((p) => ({ ...p, duration_minutes: e.target.value }))}
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">Max participants</label>
                  <input
                    type="number" min="1" className="form-input"
                    value={packageForm.max_participants}
                    onChange={(e) => setPackageForm((p) => ({ ...p, max_participants: e.target.value }))}
                  />
                </div>
              </div>

              <div className="form-grid-2">
                <div className="form-group">
                  <label className="form-label">What's included (one per line)</label>
                  <textarea
                    className="form-textarea" rows={3}
                    value={arrayToLines(packageForm.inclusions)}
                    onChange={(e) => setPackageForm((p) => ({ ...p, inclusions: linesToArray(e.target.value) }))}
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">Languages (one per line)</label>
                  <textarea
                    className="form-textarea" rows={3}
                    value={arrayToLines(packageForm.languages)}
                    onChange={(e) => setPackageForm((p) => ({ ...p, languages: linesToArray(e.target.value) }))}
                  />
                </div>
              </div>

              <ImageUploader
                label="Package photos (first is the card photo)"
                value={packageForm.photo_urls}
                onChange={(urls) => setPackageForm((p) => ({ ...p, photo_urls: urls }))}
              />

              <div className="form-group">
                <label className="form-label" style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <input
                    type="checkbox"
                    checked={!packageForm.uses_vendor_location}
                    onChange={(e) => setPackageForm((p) => ({
                      ...p,
                      uses_vendor_location: !e.target.checked,
                      latitude: e.target.checked ? (selected?.latitude ?? '') : null,
                      longitude: e.target.checked ? (selected?.longitude ?? '') : null,
                    }))}
                  />
                  This package meets somewhere other than the vendor's address
                </label>
              </div>

              {!packageForm.uses_vendor_location && (
                <>
                  <LocationPicker
                    mapId="package-location-map"
                    latitude={packageForm.latitude ?? ''}
                    longitude={packageForm.longitude ?? ''}
                    address={packageForm.meeting_point_address}
                    onPick={(patch) => {
                      const next = { ...patch };
                      delete next.name;
                      const pickedAddress = next.address;
                      delete next.address;
                      setPackageForm((p) => ({
                        ...p,
                        ...next,
                        ...(pickedAddress !== undefined
                          ? { meeting_point_address: pickedAddress }
                          : {}),
                      }));
                    }}
                  />
                </>
              )}

              <div className="form-group">
                <label className="form-label">Status</label>
                <select
                  className="form-select"
                  value={packageForm.is_active ? 'active' : 'hidden'}
                  onChange={(e) => setPackageForm((p) => ({ ...p, is_active: e.target.value === 'active' }))}
                >
                  <option value="active">Active</option>
                  <option value="hidden">Hidden</option>
                </select>
              </div>

              <div style={{ display: 'flex', gap: '10px', marginTop: '8px' }}>
                <button type="submit" className="btn btn-primary">
                  {editingPackageId ? 'Save package' : 'Create package'}
                </button>
                <button type="button" className="btn btn-ghost" onClick={() => setPackageModalOpen(false)}>
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
