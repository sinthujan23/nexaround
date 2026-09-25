import { useEffect, useState } from 'react';
import { useApi, apiGet, apiPost, apiPut, apiPatch, apiDelete, mediaUrl } from '../api';
import {
  CompassIcon, UsersIcon, PlusIcon, EditIcon, TrashIcon, SearchIcon, CrossIcon,
  TicketIcon, PhoneIcon, MailIcon, GlobeIcon, StarIcon, WhatsAppIcon,
} from '../components/Icons';
import LocationPicker from '../components/LocationPicker';
import ImageUploader from '../components/ImageUploader';
import { COUNTRIES, normalizeCountryCode } from '../constants/countries';

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
  google_place_id: '', city: '', country_code: 'LK', contact_phone: '',
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

const linesToArray = (text) =>
  text.split('\n').map((line) => line.trim()).filter(Boolean);
const arrayToLines = (arr) => (arr || []).join('\n');

const categoryLabel = (value) => CATEGORIES.find((c) => c.value === value)?.label || value || 'Other';
const basisLabel = (value) => PRICE_BASES.find((b) => b.value === value)?.label || 'Per person';

const formatPrice = (pkg) =>
  pkg.price_amount != null
    ? `${pkg.price_currency || 'LKR'} ${Number(pkg.price_amount).toLocaleString()}`
    : 'On request';

const formatDuration = (minutes) => {
  if (!minutes) return null;
  if (minutes < 60) return `${minutes} min`;
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return m ? `${h} h ${m} min` : `${h} h`;
};

const vendorToForm = (vendor) => ({
  ...emptyVendor,
  ...vendor,
  rating: vendor.rating ?? '',
  description: vendor.description || '',
  internal_notes: vendor.internal_notes || '',
  photo_urls: vendor.photo_urls || [],
});

const vendorPayload = (form) => ({
  ...form,
  latitude: Number(form.latitude),
  longitude: Number(form.longitude),
  rating: form.rating === '' ? null : Number(form.rating),
  review_count: Number(form.review_count) || 0,
  sort_order: Number(form.sort_order) || 0,
});

const matches = (query, ...fields) => {
  const q = query.trim().toLowerCase();
  return !q || fields.some((f) => (f || '').toLowerCase().includes(q));
};

// LocationPicker reports the place's name when one is picked from search; only
// take it when the vendor has no name yet.
const pickLocation = (form, patch) => {
  const next = { ...patch };
  if (next.name !== undefined && form.name) delete next.name;
  if (next.country_code) next.country_code = normalizeCountryCode(next.country_code);
  return next;
};

function Switch({ checked, onChange, label, disabled }) {
  return (
    <label className="switch" onClick={(e) => e.stopPropagation()}>
      <input type="checkbox" checked={checked} disabled={disabled} onChange={(e) => onChange(e.target.checked)} />
      <span className="switch-track" />
      {label}
    </label>
  );
}

function Drawer({ title, subtitle, onClose, footer, children, onSubmit }) {
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const Body = onSubmit ? 'form' : 'div';
  return (
    <div className="drawer-overlay" onClick={onClose}>
      <Body className="drawer" onClick={(e) => e.stopPropagation()} onSubmit={onSubmit}>
        <div className="drawer-head">
          <div>
            <div className="drawer-title">{title}</div>
            {subtitle && <div className="drawer-sub">{subtitle}</div>}
          </div>
          <button type="button" className="icon-btn" onClick={onClose} title="Close">
            <CrossIcon size={18} />
          </button>
        </div>
        <div className="drawer-body">{children}</div>
        <div className="drawer-foot">{footer}</div>
      </Body>
    </div>
  );
}

function VendorAvatar({ vendor, large }) {
  const photo = vendor.logo_url || vendor.photo_urls?.[0];
  return (
    <div className={`xp-avatar ${large ? 'lg' : ''}`}>
      {photo ? <img src={mediaUrl(photo)} alt="" /> : (vendor.name || '?').charAt(0).toUpperCase()}
    </div>
  );
}

function ContactChips({ vendor }) {
  return (
    <div className="contact-chips">
      {vendor.contact_phone && (
        <a className="icon-btn" href={`tel:${vendor.contact_phone}`} title={vendor.contact_phone}>
          <PhoneIcon size={15} />
        </a>
      )}
      {vendor.contact_whatsapp && (
        <a
          className="icon-btn whatsapp" target="_blank" rel="noreferrer" title={`WhatsApp ${vendor.contact_whatsapp}`}
          href={`https://wa.me/${vendor.contact_whatsapp.replace(/[^0-9]/g, '')}`}
        >
          <WhatsAppIcon size={15} />
        </a>
      )}
      {vendor.contact_email && (
        <a className="icon-btn" href={`mailto:${vendor.contact_email}`} title={vendor.contact_email}>
          <MailIcon size={15} />
        </a>
      )}
      {vendor.website && (
        <a className="icon-btn" href={vendor.website} target="_blank" rel="noreferrer" title={vendor.website}>
          <GlobeIcon size={15} />
        </a>
      )}
    </div>
  );
}

export default function Experiences() {
  const [view, setView] = useState('vendors'); // 'vendors' | 'packages'
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all'); // 'all' | 'live' | 'hidden'
  const [categoryFilter, setCategoryFilter] = useState('all');
  const [toast, setToast] = useState(null);

  // Selected vendor
  const [selected, setSelected] = useState(null);
  const [tab, setTab] = useState('packages');
  const [form, setForm] = useState(emptyVendor);
  const [formBase, setFormBase] = useState(emptyVendor);
  const [saving, setSaving] = useState(false);

  const [packages, setPackages] = useState([]);
  const [packagesLoading, setPackagesLoading] = useState(false);

  const [logins, setLogins] = useState([]);
  const [inviteOpen, setInviteOpen] = useState(false);
  const [loginForm, setLoginForm] = useState({ email: '', display_name: '' });
  const [loginBusy, setLoginBusy] = useState(false);

  // Drawers: 'new-vendor' | 'package' | null
  const [drawer, setDrawer] = useState(null);
  const [packageForm, setPackageForm] = useState(emptyPackage);
  const [editingPackageId, setEditingPackageId] = useState(null);
  const [packageVendorId, setPackageVendorId] = useState(null);
  const [packageSaving, setPackageSaving] = useState(false);

  // Every package across vendors, for the "All packages" view
  const [allPackages, setAllPackages] = useState([]);
  const [allPackagesKey, setAllPackagesKey] = useState(null);
  const [allPackagesVersion, setAllPackagesVersion] = useState(0);

  // One request for every vendor (the API caps page_size at 200); search and
  // filters run client-side so the two views can share them.
  const { data, error, refetch } = useApi('/admin/experiences/vendors?page=1&page_size=200');
  const vendors = data?.vendors || [];
  const vendorsLoaded = data !== null;
  const vendorKey = vendors.map((v) => v.id).join(',');
  const packagesKey = `${vendorKey}|${allPackagesVersion}`;
  const allPackagesLoading = !!vendorKey && allPackagesKey !== packagesKey;

  const notify = (message, tone = 'ok') => {
    setToast({ message, tone });
    setTimeout(() => setToast(null), 3500);
  };

  useEffect(() => {
    if (view !== 'packages' || !vendorKey) return;
    let active = true;
    // No cross-vendor packages endpoint exists, so fan out one request per vendor.
    Promise.all(
      vendors.map((v) =>
        apiGet(`/admin/experiences/vendors/${v.id}/packages`)
          .then((res) => (res.packages || []).map((pkg) => ({
            ...pkg, vendor_id: v.id, vendor_name: v.name, vendor_city: v.city,
          })))
          .catch(() => [])
      )
    ).then((lists) => {
      if (!active) return;
      setAllPackages(lists.flat());
      setAllPackagesKey(packagesKey);
    });
    return () => { active = false; };
    // vendors is derived from vendorKey; listing it would refetch on every render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [view, packagesKey]);

  const refreshAll = () => {
    refetch();
    setAllPackagesVersion((n) => n + 1);
  };

  // --- Vendor ---------------------------------------------------------------

  const loadPackages = async (vendorId) => {
    setPackagesLoading(true);
    try {
      const res = await apiGet(`/admin/experiences/vendors/${vendorId}/packages`);
      setPackages(res.packages || []);
    } catch (err) {
      notify(`Could not load packages: ${err.message}`, 'error');
      setPackages([]);
    } finally {
      setPackagesLoading(false);
    }
  };

  const loadLogins = async (vendorId) => {
    try {
      const res = await apiGet(`/admin/experiences/vendors/${vendorId}/logins`);
      setLogins(res.logins || []);
    } catch {
      setLogins([]);
    }
  };

  const isDirty = JSON.stringify(form) !== JSON.stringify(formBase);

  const selectVendor = (vendor, nextTab = 'packages') => {
    if (selected && selected.id !== vendor.id && isDirty
      && !confirm('You have unsaved changes to this vendor. Discard them?')) return;
    const next = vendorToForm(vendor);
    setSelected(vendor);
    setTab(nextTab);
    setForm(next);
    setFormBase(next);
    setInviteOpen(false);
    setPackages([]);
    setLogins([]);
    loadPackages(vendor.id);
    loadLogins(vendor.id);
  };

  const closeVendor = () => {
    if (isDirty && !confirm('You have unsaved changes to this vendor. Discard them?')) return;
    setSelected(null);
  };

  const patchForm = (patch) => setForm((prev) => ({ ...prev, ...patch }));

  const saveVendor = async () => {
    if (form.latitude === '' || form.longitude === '') {
      setTab('location');
      notify('Set the vendor location on the map first.', 'error');
      return;
    }
    setSaving(true);
    try {
      const updated = await apiPut(`/admin/experiences/vendors/${selected.id}`, vendorPayload(form));
      const next = vendorToForm(updated);
      setSelected(updated);
      setForm(next);
      setFormBase(next);
      refreshAll();
      notify('Vendor saved');
    } catch (err) {
      notify(`Could not save vendor: ${err.message}`, 'error');
    } finally {
      setSaving(false);
    }
  };

  // The live switch saves straight away, from the last saved state, so it
  // never sweeps half-finished edits in with it.
  const toggleVendorLive = async (isActive) => {
    try {
      const updated = await apiPut(
        `/admin/experiences/vendors/${selected.id}`,
        vendorPayload({ ...formBase, is_active: isActive })
      );
      setSelected(updated);
      setFormBase((prev) => ({ ...prev, is_active: updated.is_active }));
      setForm((prev) => ({ ...prev, is_active: updated.is_active }));
      refreshAll();
      notify(isActive ? `${updated.name} is live in the app` : `${updated.name} is hidden from the app`);
    } catch (err) {
      notify(`Could not update vendor: ${err.message}`, 'error');
    }
  };

  const deleteVendor = async () => {
    if (!confirm(`Delete "${selected.name}" and all of its packages? This cannot be undone.`)) return;
    try {
      await apiDelete(`/admin/experiences/vendors/${selected.id}`);
      setSelected(null);
      refreshAll();
      notify('Vendor deleted');
    } catch (err) {
      notify(`Could not delete vendor: ${err.message}`, 'error');
    }
  };

  const openNewVendor = () => {
    if (isDirty && !confirm('You have unsaved changes to this vendor. Discard them?')) return;
    setSelected(null);
    setForm(emptyVendor);
    setFormBase(emptyVendor);
    setDrawer('new-vendor');
  };

  const createVendor = async (e) => {
    e.preventDefault();
    if (form.latitude === '' || form.longitude === '') {
      notify('Set the vendor location on the map first.', 'error');
      return;
    }
    setSaving(true);
    try {
      const created = await apiPost('/admin/experiences/vendors', vendorPayload(form));
      setDrawer(null);
      setView('vendors');
      refreshAll();
      selectVendor(created, 'packages');
      notify('Vendor created. Add its first package next.');
    } catch (err) {
      notify(`Could not create vendor: ${err.message}`, 'error');
    } finally {
      setSaving(false);
    }
  };

  // --- Packages -------------------------------------------------------------

  const afterPackageChange = (vendorId) => {
    if (selected && selected.id === vendorId) loadPackages(vendorId);
    refreshAll();
  };

  const openNewPackage = () => {
    setPackageVendorId(selected.id);
    setEditingPackageId(null);
    setPackageForm(emptyPackage);
    setDrawer('package');
  };

  const openEditPackage = (pkg) => {
    setPackageVendorId(pkg.vendor_id || selected?.id);
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
    setDrawer('package');
  };

  const patchPackage = (patch) => setPackageForm((prev) => ({ ...prev, ...patch }));

  const savePackage = async (e) => {
    e.preventDefault();
    if (!packageForm.uses_vendor_location
      && [packageForm.latitude, packageForm.longitude].some((v) => v == null || v === '')) {
      notify('Pick the meeting point on the map, or use the vendor address.', 'error');
      return;
    }
    const payload = {
      ...packageForm,
      price_amount: packageForm.price_amount === '' ? null : Number(packageForm.price_amount),
      duration_minutes: packageForm.duration_minutes === '' ? null : Number(packageForm.duration_minutes),
      max_participants: packageForm.max_participants === '' ? null : Number(packageForm.max_participants),
      sort_order: Number(packageForm.sort_order) || 0,
      latitude: packageForm.uses_vendor_location ? null : Number(packageForm.latitude),
      longitude: packageForm.uses_vendor_location ? null : Number(packageForm.longitude),
    };
    setPackageSaving(true);
    try {
      if (editingPackageId) {
        await apiPut(`/admin/experiences/packages/${editingPackageId}`, payload);
      } else {
        await apiPost(`/admin/experiences/vendors/${packageVendorId}/packages`, payload);
      }
      setDrawer(null);
      afterPackageChange(packageVendorId);
      notify(editingPackageId ? 'Package saved' : 'Package created');
    } catch (err) {
      notify(`Could not save package: ${err.message}`, 'error');
    } finally {
      setPackageSaving(false);
    }
  };

  const deletePackage = async (pkg) => {
    if (!confirm(`Delete "${pkg.title}"? This cannot be undone.`)) return;
    try {
      await apiDelete(`/admin/experiences/packages/${pkg.id}`);
      if (drawer === 'package') setDrawer(null);
      afterPackageChange(pkg.vendor_id);
      notify('Package deleted');
    } catch (err) {
      notify(`Could not delete package: ${err.message}`, 'error');
    }
  };

  const togglePackageLive = async (pkg, isActive) => {
    // Optimistic, so the switch moves under the cursor.
    const flip = (list) => list.map((p) => (p.id === pkg.id ? { ...p, is_active: isActive } : p));
    setPackages(flip);
    setAllPackages(flip);
    try {
      await apiPut(`/admin/experiences/packages/${pkg.id}`, { ...pkg, is_active: isActive });
      refetch();
    } catch (err) {
      const undo = (list) => list.map((p) => (p.id === pkg.id ? { ...p, is_active: !isActive } : p));
      setPackages(undo);
      setAllPackages(undo);
      notify(`Could not update package: ${err.message}`, 'error');
    }
  };

  // --- Partner logins -------------------------------------------------------

  const createLogin = async (e) => {
    e.preventDefault();
    setLoginBusy(true);
    try {
      await apiPost(`/admin/experiences/vendors/${selected.id}/logins`, loginForm);
      setInviteOpen(false);
      setLoginForm({ email: '', display_name: '' });
      loadLogins(selected.id);
      notify(`Invite sent to ${loginForm.email}`);
    } catch (err) {
      notify(`Could not create the login: ${err.message}`, 'error');
    } finally {
      setLoginBusy(false);
    }
  };

  const resendInvite = async (login) => {
    try {
      const res = await apiPost(`/admin/experiences/logins/${login.id}/resend-invite`, {});
      if (res && res.reset_link) {
        await navigator.clipboard.writeText(res.reset_link);
        notify(`Link for ${login.email} copied to clipboard`);
      } else {
        notify(`A new link was emailed to ${login.email}`);
      }
    } catch (err) {
      notify(`Could not send the link: ${err.message}`, 'error');
    }
  };

  const toggleLogin = async (login) => {
    try {
      await apiPatch(`/admin/experiences/logins/${login.id}`, { is_active: !login.is_active });
      loadLogins(selected.id);
    } catch (err) {
      notify(`Could not update the login: ${err.message}`, 'error');
    }
  };

  const deleteLogin = async (login) => {
    if (!confirm(`Remove the login for ${login.email}? They lose access immediately.`)) return;
    try {
      await apiDelete(`/admin/experiences/logins/${login.id}`);
      loadLogins(selected.id);
    } catch (err) {
      notify(`Could not remove the login: ${err.message}`, 'error');
    }
  };

  // --- Derived lists --------------------------------------------------------

  const liveVendors = vendors.filter((v) => v.is_active).length;
  const totalPackages = vendors.reduce((acc, v) => acc + (v.package_count || 0), 0);

  const passesStatus = (isActive) =>
    statusFilter === 'all' || (statusFilter === 'live' ? isActive : !isActive);

  const filteredVendors = vendors.filter((v) =>
    passesStatus(v.is_active) && matches(search, v.name, v.city, v.address, v.contact_email)
  );

  const filteredPackages = allPackages.filter((pkg) =>
    passesStatus(pkg.is_active)
    && (categoryFilter === 'all' || pkg.category === categoryFilter)
    && matches(search, pkg.title, pkg.vendor_name, pkg.vendor_city, categoryLabel(pkg.category))
  );

  const packageVendor = vendors.find((v) => v.id === packageVendorId) || selected;
  const editableTab = ['details', 'location', 'contact'].includes(tab);

  return (
    <div>
      <div className="xp-toolbar">
        <div className="seg">
          <button className={`seg-btn ${view === 'vendors' ? 'active' : ''}`} onClick={() => setView('vendors')}>
            Vendors <span className="seg-count">{vendors.length}</span>
          </button>
          <button className={`seg-btn ${view === 'packages' ? 'active' : ''}`} onClick={() => setView('packages')}>
            All packages <span className="seg-count">{totalPackages}</span>
          </button>
        </div>

        <div className="xp-toolbar-right">
          <div className="search-bar">
            <SearchIcon size={16} />
            <input
              type="text" value={search} onChange={(e) => setSearch(e.target.value)}
              placeholder={view === 'vendors' ? 'Search vendors or cities…' : 'Search packages or vendors…'}
            />
          </div>
          {view === 'packages' && (
            <select className="xp-select" value={categoryFilter} onChange={(e) => setCategoryFilter(e.target.value)}>
              <option value="all">All categories</option>
              {CATEGORIES.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
            </select>
          )}
          <select className="xp-select" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
            <option value="all">Any status</option>
            <option value="live">Live</option>
            <option value="hidden">Hidden</option>
          </select>
          <button className="btn btn-primary btn-sm" onClick={openNewVendor}>
            <PlusIcon size={15} /> New vendor
          </button>
        </div>
      </div>

      {error && <div className="login-error">{error}</div>}

      {/* ===== Vendors: list + detail ===== */}
      {view === 'vendors' && (
        <div className={`xp-split ${selected ? 'has-selection' : ''}`}>
          <aside className="xp-pane xp-list-pane">
            <div className="xp-list-head">
              <span>{filteredVendors.length} of {vendors.length} vendors</span>
              <span>{liveVendors} live</span>
            </div>
            <div className="xp-list-body">
              {!vendorsLoaded && <div className="loader" />}
              {vendorsLoaded && filteredVendors.length === 0 && (
                <div className="xp-empty">
                  <strong>No vendors found</strong>
                  {search || statusFilter !== 'all' ? 'Try a different search or status.' : 'Add your first vendor to get started.'}
                </div>
              )}
              {filteredVendors.map((vendor) => (
                <button
                  key={vendor.id}
                  className={`xp-row ${selected?.id === vendor.id ? 'active' : ''}`}
                  onClick={() => selectVendor(vendor)}
                >
                  <VendorAvatar vendor={vendor} />
                  <div className="xp-row-main">
                    <div className="xp-row-title">{vendor.name}</div>
                    <div className="xp-row-sub">
                      {vendor.city || 'No city'} · {vendor.package_count} {vendor.package_count === 1 ? 'package' : 'packages'}
                    </div>
                  </div>
                  <div className="xp-row-side">
                    <span className={`dot ${vendor.is_active ? 'dot-live' : 'dot-hidden'}`} title={vendor.is_active ? 'Live' : 'Hidden'} />
                    {vendor.rating ? (
                      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3, color: '#d97706' }}>
                        <StarIcon size={11} /> {vendor.rating}
                      </span>
                    ) : null}
                  </div>
                </button>
              ))}
            </div>
          </aside>

          <section className="xp-pane xp-detail-pane">
            {!selected && (
              <div className="xp-empty">
                <CompassIcon size={36} />
                <strong>Select a vendor</strong>
                Their packages, details and partner logins open here.
              </div>
            )}

            {selected && (
              <>
                <div className="xp-detail-head">
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <button className="xp-back" onClick={closeVendor}>← All vendors</button>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
                      <VendorAvatar vendor={selected} large />
                      <div style={{ minWidth: 0 }}>
                        <div className="xp-detail-title">{selected.name}</div>
                        <div className="xp-detail-sub">
                          {[selected.city, selected.address].filter(Boolean).join(' · ') || 'No location yet'}
                        </div>
                      </div>
                    </div>
                  </div>
                  <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 10 }}>
                    <Switch
                      checked={!!formBase.is_active}
                      onChange={toggleVendorLive}
                      label={formBase.is_active ? 'Live in app' : 'Hidden'}
                    />
                    <ContactChips vendor={selected} />
                  </div>
                </div>

                <div className="xp-tabs">
                  {[
                    ['packages', `Packages · ${packages.length}`],
                    ['details', 'Details'],
                    ['location', 'Location'],
                    ['contact', 'Contact'],
                    ['portal', `Partner portal · ${logins.length}`],
                  ].map(([key, label]) => (
                    <button key={key} className={`xp-tab ${tab === key ? 'active' : ''}`} onClick={() => setTab(key)}>
                      {label}
                    </button>
                  ))}
                </div>

                <div className="xp-body">
                  {tab === 'packages' && (
                    <div>
                      <div className="xp-section-head">
                        <div className="xp-section-hint">Each package shows in the app as its own bookable experience.</div>
                        {packages.length > 0 && (
                          <button className="btn btn-primary btn-sm" onClick={openNewPackage}>
                            <PlusIcon size={14} /> Add package
                          </button>
                        )}
                      </div>

                      {packagesLoading && <div className="loader" />}

                      {!packagesLoading && packages.length === 0 && (
                        <div className="xp-placeholder">
                          <TicketIcon size={28} />
                          <strong>No packages yet</strong>
                          Add the tours, rides or activities travellers can enquire about.
                          <div>
                            <button className="btn btn-primary btn-sm" onClick={openNewPackage}>
                              <PlusIcon size={14} /> Add first package
                            </button>
                          </div>
                        </div>
                      )}

                      {!packagesLoading && packages.map((pkg) => (
                        <div key={pkg.id} className="pkg-row">
                          <div className="pkg-thumb">
                            {pkg.photo_urls?.[0] ? <img src={mediaUrl(pkg.photo_urls[0])} alt="" /> : <TicketIcon size={18} />}
                          </div>
                          <div className="pkg-row-main">
                            <div className="pkg-row-title">{pkg.title}</div>
                            <div className="pkg-row-meta">
                              <span className="pkg-price">{formatPrice(pkg)}</span>
                              <span>{categoryLabel(pkg.category)}</span>
                              {pkg.duration_minutes ? <span>{formatDuration(pkg.duration_minutes)}</span> : null}
                              {pkg.max_participants ? <span>Up to {pkg.max_participants}</span> : null}
                            </div>
                          </div>
                          <div className="pkg-row-actions">
                            <Switch checked={pkg.is_active} onChange={(v) => togglePackageLive(pkg, v)} />
                            <button className="icon-btn" title="Edit" onClick={() => openEditPackage(pkg)}>
                              <EditIcon size={15} />
                            </button>
                            <button className="icon-btn danger" title="Delete" onClick={() => deletePackage(pkg)}>
                              <TrashIcon size={15} />
                            </button>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}

                  {tab === 'details' && (
                    <div>
                      <div className="xp-section">
                        <div className="form-group">
                          <label className="form-label">Name</label>
                          <input
                            type="text" required className="form-input" value={form.name}
                            onChange={(e) => patchForm({ name: e.target.value })}
                          />
                        </div>
                        <div className="form-group">
                          <label className="form-label">Description</label>
                          <textarea
                            className="form-textarea" rows={3} value={form.description}
                            placeholder="What the business does, in a sentence or two"
                            onChange={(e) => patchForm({ description: e.target.value })}
                          />
                        </div>
                        <ImageUploader
                          label="Photos"
                          value={form.photo_urls}
                          onChange={(urls) => patchForm({ photo_urls: urls })}
                        />
                      </div>

                      <div className="xp-section">
                        <div className="xp-section-title">Rating & ordering</div>
                        <div className="xp-section-hint">Rating is optional and shown as-is in the app.</div>
                        <div className="form-grid-3">
                          <div className="form-group">
                            <label className="form-label">Rating (0–5)</label>
                            <input
                              type="number" step="0.1" min="0" max="5" className="form-input"
                              value={form.rating} placeholder="4.8"
                              onChange={(e) => patchForm({ rating: e.target.value })}
                            />
                          </div>
                          <div className="form-group">
                            <label className="form-label">Reviews</label>
                            <input
                              type="number" min="0" className="form-input" value={form.review_count || 0}
                              onChange={(e) => patchForm({ review_count: e.target.value })}
                            />
                          </div>
                          <div className="form-group">
                            <label className="form-label">Sort order</label>
                            <input
                              type="number" className="form-input" value={form.sort_order || 0}
                              onChange={(e) => patchForm({ sort_order: e.target.value })}
                            />
                          </div>
                        </div>
                      </div>

                      <div className="xp-section">
                        <div className="xp-section-title">Internal notes</div>
                        <div className="xp-section-hint">Only admins see these.</div>
                        <textarea
                          className="form-textarea" rows={3} value={form.internal_notes}
                          onChange={(e) => patchForm({ internal_notes: e.target.value })}
                        />
                      </div>

                      <div className="xp-danger">
                        <span>Deleting removes this vendor and every one of its packages.</span>
                        <button className="btn btn-danger-ghost btn-sm" onClick={deleteVendor}>
                          <TrashIcon size={14} /> Delete vendor
                        </button>
                      </div>
                    </div>
                  )}

                  {tab === 'location' && (
                    <div>
                      <div className="form-grid-2">
                        <div className="form-group">
                          <label className="form-label">City</label>
                          <input
                            type="text" className="form-input" value={form.city || ''} placeholder="Trincomalee"
                            onChange={(e) => patchForm({ city: e.target.value })}
                          />
                        </div>
                        <div className="form-group">
                          <label className="form-label">Country</label>
                          <select
                            className="form-input"
                            value={normalizeCountryCode(form.country_code || 'LK')}
                            onChange={(e) => patchForm({ country_code: e.target.value })}
                          >
                            {COUNTRIES.map((c) => (
                              <option key={c.code} value={c.code}>
                                {c.flag} {c.name} ({c.code})
                              </option>
                            ))}
                          </select>
                        </div>
                      </div>
                      <label className="form-label">Map pin</label>
                      <LocationPicker
                        mapId="vendor-detail-map"
                        latitude={form.latitude}
                        longitude={form.longitude}
                        address={form.address}
                        onPick={(patch) => patchForm(pickLocation(form, patch))}
                      />
                    </div>
                  )}

                  {tab === 'contact' && (
                    <div>
                      <div className="xp-section">
                        <div className="xp-section-title">Direct contact</div>
                        <div className="xp-section-hint">The email also receives new enquiry notifications.</div>
                        <div className="form-grid-2">
                          <div className="form-group">
                            <label className="form-label">Phone</label>
                            <input
                              type="text" className="form-input" value={form.contact_phone || ''} placeholder="+94 77 123 4567"
                              onChange={(e) => patchForm({ contact_phone: e.target.value })}
                            />
                          </div>
                          <div className="form-group">
                            <label className="form-label">WhatsApp</label>
                            <input
                              type="text" className="form-input" value={form.contact_whatsapp || ''} placeholder="+94 77 123 4567"
                              onChange={(e) => patchForm({ contact_whatsapp: e.target.value })}
                            />
                          </div>
                          <div className="form-group">
                            <label className="form-label">Email</label>
                            <input
                              type="email" className="form-input" value={form.contact_email || ''} placeholder="bookings@vendor.com"
                              onChange={(e) => patchForm({ contact_email: e.target.value })}
                            />
                          </div>
                          <div className="form-group">
                            <label className="form-label">Website</label>
                            <input
                              type="text" className="form-input" value={form.website || ''} placeholder="https://vendor.com"
                              onChange={(e) => patchForm({ website: e.target.value })}
                            />
                          </div>
                        </div>
                      </div>
                      <div className="xp-section">
                        <div className="xp-section-title">Social</div>
                        <div className="xp-section-hint">A handle or a full URL both work.</div>
                        <div className="form-grid-3">
                          <div className="form-group">
                            <label className="form-label">Instagram</label>
                            <input
                              type="text" className="form-input" value={form.contact_instagram || ''} placeholder="@handle"
                              onChange={(e) => patchForm({ contact_instagram: e.target.value })}
                            />
                          </div>
                          <div className="form-group">
                            <label className="form-label">Facebook</label>
                            <input
                              type="text" className="form-input" value={form.contact_facebook || ''} placeholder="Page URL"
                              onChange={(e) => patchForm({ contact_facebook: e.target.value })}
                            />
                          </div>
                          <div className="form-group">
                            <label className="form-label">X / Twitter</label>
                            <input
                              type="text" className="form-input" value={form.contact_x || ''} placeholder="@handle"
                              onChange={(e) => patchForm({ contact_x: e.target.value })}
                            />
                          </div>
                        </div>
                      </div>
                    </div>
                  )}

                  {tab === 'portal' && (
                    <div>
                      <div className="xp-section-head">
                        <div className="xp-section-hint">
                          People who can sign in at partner.nexaround.com to edit this vendor's packages and answer its enquiries.
                        </div>
                        {!inviteOpen && (
                          <button className="btn btn-primary btn-sm" onClick={() => setInviteOpen(true)}>
                            <PlusIcon size={14} /> Invite
                          </button>
                        )}
                      </div>

                      {inviteOpen && (
                        <form className="inline-form" onSubmit={createLogin}>
                          <div className="form-grid-2">
                            <div className="form-group">
                              <label className="form-label">Email</label>
                              <input
                                type="email" required autoFocus className="form-input" placeholder="owner@business.com"
                                value={loginForm.email}
                                onChange={(e) => setLoginForm({ ...loginForm, email: e.target.value })}
                              />
                            </div>
                            <div className="form-group">
                              <label className="form-label">Name (optional)</label>
                              <input
                                type="text" className="form-input" placeholder="Nimal Perera"
                                value={loginForm.display_name}
                                onChange={(e) => setLoginForm({ ...loginForm, display_name: e.target.value })}
                              />
                            </div>
                          </div>
                          <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end', marginTop: 12 }}>
                            <button type="button" className="btn btn-ghost btn-sm" onClick={() => setInviteOpen(false)}>Cancel</button>
                            <button type="submit" className="btn btn-primary btn-sm" disabled={loginBusy}>
                              {loginBusy ? 'Sending…' : 'Send invite'}
                            </button>
                          </div>
                        </form>
                      )}

                      {logins.length === 0 && !inviteOpen && (
                        <div className="xp-placeholder">
                          <UsersIcon size={28} />
                          <strong>No partner logins</strong>
                          Invite the business owner so they can manage their own listings.
                        </div>
                      )}

                      {logins.map((login) => (
                        <div key={login.id} className="login-row">
                          <div className="xp-avatar">{(login.display_name || login.email).charAt(0).toUpperCase()}</div>
                          <div className="pkg-row-main">
                            <div className="pkg-row-title">{login.display_name || login.email}</div>
                            <div className="pkg-row-meta">
                              {login.display_name && <span>{login.email}</span>}
                              {login.invited_at && <span>Invited {new Date(login.invited_at).toLocaleDateString('en-GB')}</span>}
                            </div>
                          </div>
                          <button className="btn btn-ghost btn-sm" onClick={() => resendInvite(login)}>
                            New link
                          </button>
                          <Switch
                            checked={login.is_active}
                            onChange={() => toggleLogin(login)}
                            label={login.is_active ? 'Active' : 'Disabled'}
                          />
                          <button className="icon-btn danger" title="Remove login" onClick={() => deleteLogin(login)}>
                            <TrashIcon size={15} />
                          </button>
                        </div>
                      ))}
                    </div>
                  )}
                </div>

                {editableTab && (
                  <div className="xp-savebar">
                    {isDirty
                      ? <span className="unsaved"><span className="dot dot-new" /> Unsaved changes</span>
                      : <span>All changes saved</span>}
                    <div style={{ display: 'flex', gap: 8 }}>
                      {isDirty && (
                        <button className="btn btn-ghost btn-sm" onClick={() => setForm(formBase)}>Discard</button>
                      )}
                      <button className="btn btn-primary btn-sm" disabled={!isDirty || saving} onClick={saveVendor}>
                        {saving ? 'Saving…' : 'Save changes'}
                      </button>
                    </div>
                  </div>
                )}
              </>
            )}
          </section>
        </div>
      )}

      {/* ===== All packages gallery ===== */}
      {view === 'packages' && (
        <div>
          {allPackagesLoading && allPackages.length === 0 && <div className="loader" />}

          {!allPackagesLoading && filteredPackages.length === 0 && (
            <div className="card xp-empty" style={{ padding: 48 }}>
              <TicketIcon size={36} />
              <strong>No packages match</strong>
              {allPackages.length ? 'Try a different search, category or status.' : 'Open a vendor to add its first package.'}
            </div>
          )}

          {filteredPackages.length > 0 && (
            <div className="pkg-grid">
              {filteredPackages.map((pkg) => (
                <div
                  key={pkg.id}
                  className={`pkg-card ${pkg.is_active ? '' : 'is-hidden'}`}
                  onClick={() => openEditPackage(pkg)}
                >
                  <div className="pkg-card-img">
                    {pkg.photo_urls?.[0] ? <img src={mediaUrl(pkg.photo_urls[0])} alt="" /> : <TicketIcon size={28} />}
                  </div>
                  <div className="pkg-card-body">
                    <div className="pkg-eyebrow">{categoryLabel(pkg.category)}</div>
                    <div className="pkg-card-title">{pkg.title}</div>
                    <div className="pkg-card-vendor">
                      {pkg.vendor_name}{pkg.vendor_city ? ` · ${pkg.vendor_city}` : ''}
                    </div>
                    <div className="pkg-card-foot">
                      <div>
                        <div className="pkg-price">{formatPrice(pkg)}</div>
                        <div className="sub">
                          {basisLabel(pkg.price_basis)}
                          {pkg.duration_minutes ? ` · ${formatDuration(pkg.duration_minutes)}` : ''}
                        </div>
                      </div>
                      <Switch
                        checked={pkg.is_active}
                        onChange={(v) => togglePackageLive(pkg, v)}
                        label={pkg.is_active ? 'Live' : 'Hidden'}
                      />
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* ===== New vendor drawer ===== */}
      {drawer === 'new-vendor' && (
        <Drawer
          title="New vendor"
          subtitle="The essentials. Photos, socials and notes can be added afterwards."
          onClose={() => setDrawer(null)}
          onSubmit={createVendor}
          footer={
            <>
              <span />
              <div className="drawer-foot-actions">
                <button type="button" className="btn btn-ghost btn-sm" onClick={() => setDrawer(null)}>Cancel</button>
                <button type="submit" className="btn btn-primary btn-sm" disabled={saving}>
                  {saving ? 'Creating…' : 'Create vendor'}
                </button>
              </div>
            </>
          }
        >
          <div className="xp-section">
            <div className="form-group">
              <label className="form-label">Business name *</label>
              <input
                type="text" required autoFocus className="form-input" value={form.name}
                placeholder="Trincomalee Coastal Boat Tours"
                onChange={(e) => patchForm({ name: e.target.value })}
              />
            </div>
            <div className="form-group">
              <label className="form-label">Description</label>
              <textarea
                className="form-textarea" rows={2} value={form.description}
                placeholder="What the business does, in a sentence or two"
                onChange={(e) => patchForm({ description: e.target.value })}
              />
            </div>
          </div>

          <div className="xp-section">
            <div className="xp-section-title">Location</div>
            <div className="xp-section-hint">Search for the business or drop a pin. Required.</div>
            <div className="form-grid-2">
              <div className="form-group">
                <label className="form-label">City *</label>
                <input
                  type="text" required className="form-input" value={form.city || ''} placeholder="Trincomalee"
                  onChange={(e) => patchForm({ city: e.target.value })}
                />
              </div>
              <div className="form-group">
                <label className="form-label">Country</label>
                <select
                  className="form-input"
                  value={normalizeCountryCode(form.country_code || 'LK')}
                  onChange={(e) => patchForm({ country_code: e.target.value })}
                >
                  {COUNTRIES.map((c) => (
                    <option key={c.code} value={c.code}>
                      {c.flag} {c.name} ({c.code})
                    </option>
                  ))}
                </select>
              </div>
            </div>
            <LocationPicker
              mapId="new-vendor-map"
              latitude={form.latitude}
              longitude={form.longitude}
              address={form.address}
              onPick={(patch) => patchForm(pickLocation(form, patch))}
            />
          </div>

          <div className="xp-section">
            <div className="xp-section-title">Contact</div>
            <div className="form-grid-2">
              <div className="form-group">
                <label className="form-label">Phone</label>
                <input
                  type="text" className="form-input" value={form.contact_phone || ''} placeholder="+94 77 123 4567"
                  onChange={(e) => patchForm({ contact_phone: e.target.value })}
                />
              </div>
              <div className="form-group">
                <label className="form-label">WhatsApp</label>
                <input
                  type="text" className="form-input" value={form.contact_whatsapp || ''} placeholder="+94 77 123 4567"
                  onChange={(e) => patchForm({ contact_whatsapp: e.target.value })}
                />
              </div>
            </div>
            <div className="form-group">
              <label className="form-label">Email</label>
              <input
                type="email" className="form-input" value={form.contact_email || ''} placeholder="bookings@vendor.com"
                onChange={(e) => patchForm({ contact_email: e.target.value })}
              />
            </div>
          </div>
        </Drawer>
      )}

      {/* ===== Package drawer ===== */}
      {drawer === 'package' && (
        <Drawer
          title={editingPackageId ? 'Edit package' : 'New package'}
          subtitle={packageVendor ? `For ${packageVendor.name}` : undefined}
          onClose={() => setDrawer(null)}
          onSubmit={savePackage}
          footer={
            <>
              <Switch
                checked={packageForm.is_active}
                onChange={(v) => patchPackage({ is_active: v })}
                label={packageForm.is_active ? 'Live in app' : 'Hidden (draft)'}
              />
              <div className="drawer-foot-actions">
                {editingPackageId && (
                  <button
                    type="button" className="icon-btn danger" title="Delete package"
                    onClick={() => deletePackage({ ...packageForm, id: editingPackageId, vendor_id: packageVendorId })}
                  >
                    <TrashIcon size={15} />
                  </button>
                )}
                <button type="button" className="btn btn-ghost btn-sm" onClick={() => setDrawer(null)}>Cancel</button>
                <button type="submit" className="btn btn-primary btn-sm" disabled={packageSaving}>
                  {packageSaving ? 'Saving…' : editingPackageId ? 'Save package' : 'Create package'}
                </button>
              </div>
            </>
          }
        >
          <div className="xp-section">
            <div className="form-group">
              <label className="form-label">Title *</label>
              <input
                type="text" required autoFocus className="form-input" value={packageForm.title}
                placeholder="Pigeon Island snorkelling & boat safari"
                onChange={(e) => patchPackage({ title: e.target.value })}
              />
            </div>
            <div className="form-grid-2">
              <div className="form-group">
                <label className="form-label">Category</label>
                <select
                  className="form-select" value={packageForm.category}
                  onChange={(e) => patchPackage({ category: e.target.value })}
                >
                  {CATEGORIES.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
                </select>
              </div>
              <div className="form-group">
                <label className="form-label">Sort order</label>
                <input
                  type="number" className="form-input" value={packageForm.sort_order || 0}
                  onChange={(e) => patchPackage({ sort_order: e.target.value })}
                />
              </div>
            </div>
            <div className="form-group">
              <label className="form-label">Summary</label>
              <input
                type="text" className="form-input" value={packageForm.summary || ''} maxLength={500}
                placeholder="One line for the card in the app"
                onChange={(e) => patchPackage({ summary: e.target.value })}
              />
            </div>
            <div className="form-group">
              <label className="form-label">Description</label>
              <textarea
                className="form-textarea" rows={4} value={packageForm.description || ''}
                placeholder="Itinerary, what to bring, safety notes…"
                onChange={(e) => patchPackage({ description: e.target.value })}
              />
            </div>
          </div>

          <div className="xp-section">
            <div className="xp-section-title">Price & capacity</div>
            <div className="xp-section-hint">Leave the price empty to show “On request”.</div>
            <div className="form-grid-3">
              <div className="form-group">
                <label className="form-label">Price</label>
                <input
                  type="number" step="0.01" min="0" className="form-input" placeholder="7500"
                  value={packageForm.price_amount}
                  onChange={(e) => patchPackage({ price_amount: e.target.value })}
                />
              </div>
              <div className="form-group">
                <label className="form-label">Currency</label>
                <input
                  type="text" maxLength={4} className="form-input" value={packageForm.price_currency || 'LKR'}
                  onChange={(e) => patchPackage({ price_currency: e.target.value.toUpperCase() })}
                />
              </div>
              <div className="form-group">
                <label className="form-label">Basis</label>
                <select
                  className="form-select" value={packageForm.price_basis}
                  onChange={(e) => patchPackage({ price_basis: e.target.value })}
                >
                  {PRICE_BASES.map((b) => <option key={b.value} value={b.value}>{b.label}</option>)}
                </select>
              </div>
            </div>
            <div className="form-grid-2">
              <div className="form-group">
                <label className="form-label">Duration (minutes)</label>
                <input
                  type="number" min="0" className="form-input" placeholder="180"
                  value={packageForm.duration_minutes}
                  onChange={(e) => patchPackage({ duration_minutes: e.target.value })}
                />
              </div>
              <div className="form-group">
                <label className="form-label">Max participants</label>
                <input
                  type="number" min="1" className="form-input" placeholder="8"
                  value={packageForm.max_participants}
                  onChange={(e) => patchPackage({ max_participants: e.target.value })}
                />
              </div>
            </div>
          </div>

          <div className="xp-section">
            <ImageUploader
              label="Photos"
              value={packageForm.photo_urls}
              onChange={(urls) => patchPackage({ photo_urls: urls })}
            />
          </div>

          <div className="xp-section">
            <div className="xp-section-title">Included & languages</div>
            <div className="xp-section-hint">One item per line.</div>
            <div className="form-grid-2">
              <div className="form-group">
                <label className="form-label">What's included</label>
                <textarea
                  className="form-textarea" rows={4} value={arrayToLines(packageForm.inclusions)}
                  placeholder={'Snorkelling gear\nLife jackets\nBottled water'}
                  onChange={(e) => patchPackage({ inclusions: linesToArray(e.target.value) })}
                />
              </div>
              <div className="form-group">
                <label className="form-label">Languages</label>
                <textarea
                  className="form-textarea" rows={4} value={arrayToLines(packageForm.languages)}
                  placeholder={'English\nTamil\nSinhala'}
                  onChange={(e) => patchPackage({ languages: linesToArray(e.target.value) })}
                />
              </div>
            </div>
          </div>

          <div className="xp-section">
            <div className="xp-section-head">
              <div>
                <div className="xp-section-title">Meeting point</div>
                <div className="xp-section-hint">Where travellers meet the vendor.</div>
              </div>
              <Switch
                checked={packageForm.uses_vendor_location}
                onChange={(v) => patchPackage({ uses_vendor_location: v })}
                label="Vendor's address"
              />
            </div>
            {!packageForm.uses_vendor_location && (
              <LocationPicker
                mapId="package-meeting-map"
                latitude={packageForm.latitude ?? ''}
                longitude={packageForm.longitude ?? ''}
                address={packageForm.meeting_point_address}
                // The picker reports only what changed (typing a latitude sends
                // just the latitude), so merge rather than overwrite all three.
                onPick={({ latitude, longitude, address }) =>
                  setPackageForm((prev) => ({
                    ...prev,
                    ...(latitude !== undefined ? { latitude } : {}),
                    ...(longitude !== undefined ? { longitude } : {}),
                    ...(address !== undefined ? { meeting_point_address: address } : {}),
                  }))
                }
              />
            )}
          </div>
        </Drawer>
      )}

      {toast && <div className={`xp-toast ${toast.tone === 'error' ? 'error' : ''}`}>{toast.message}</div>}
    </div>
  );
}
