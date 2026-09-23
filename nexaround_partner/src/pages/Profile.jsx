import { useEffect, useState } from 'react';
import { apiGet, apiPut, mediaUrl } from '../api';
import { StarIcon, CompassIcon, ImageIcon, MapPinIcon, PhoneIcon, GlobeIcon } from '../components/Icons';
import { Toast, Section } from '../components/Kit';
import LocationPicker from '../components/LocationPicker';
import ImageUploader from '../components/ImageUploader';

/**
 * The vendor's own record.
 *
 * Mirrors the admin vendor form minus everything the platform reserves:
 * Active/Hidden, rating, review count, internal notes and sort order have no
 * inputs here. That is presentation only — the server drops those fields even
 * if a crafted request carries them.
 */
export default function Profile({ onSaved }) {
  const [form, setForm] = useState(null);
  const [base, setBase] = useState(null);
  const [tab, setTab] = useState('details');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [toast, setToast] = useState(null);

  useEffect(() => {
    apiGet('/partner/profile')
      .then((profile) => { setForm(profile); setBase(profile); })
      .catch((err) => setError(err.message || 'Could not load your profile.'));
  }, []);

  const notify = (message, tone = 'ok') => {
    setToast({ message, tone });
    setTimeout(() => setToast(null), 3500);
  };

  const patch = (p) => setForm((prev) => ({ ...prev, ...p }));

  const save = async () => {
    if (form.latitude === '' || form.latitude == null) {
      setTab('location');
      notify('Set your location on the map first.', 'error');
      return;
    }
    setSaving(true);
    try {
      const updated = await apiPut('/partner/profile', {
        ...form,
        latitude: Number(form.latitude),
        longitude: Number(form.longitude),
      });
      setForm(updated);
      setBase(updated);
      notify('Saved. Travellers see this straight away.');
      // The sidebar shows the business name, so a rename must reach it.
      if (onSaved) {
        onSaved((prev) => (prev ? { ...prev, vendor_name: updated.name } : prev));
      }
    } catch (err) {
      notify(err.message || 'Could not save.', 'error');
    } finally {
      setSaving(false);
    }
  };

  if (error && !form) return <div className="login-error">{error}</div>;
  if (!form) return <div className="loader" />;

  const dirty = JSON.stringify(form) !== JSON.stringify(base);
  const photo = base.logo_url || base.photo_urls?.[0];

  const TABS = [
    ['details', 'Details'],
    ['location', 'Location'],
    ['contact', 'Contact & social'],
  ];

  return (
    <div className="xp-pane xp-fill">
      <div className="xp-detail-head">
        <div className="xp-avatar lg">
          {photo ? <img src={mediaUrl(photo)} alt="" /> : (base.name || '?').charAt(0).toUpperCase()}
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div className="xp-detail-title">{base.name}</div>
          <div className="xp-detail-sub">
            {[base.city, `${base.package_count} ${base.package_count === 1 ? 'package' : 'packages'}`].filter(Boolean).join(' · ')}
            {base.rating != null && (
              <span style={{ marginLeft: 10, color: '#d97706', fontWeight: 700, display: 'inline-flex', alignItems: 'center', gap: 3 }}>
                <StarIcon size={12} /> {base.rating}
                <span style={{ color: 'var(--text-muted)', fontWeight: 500 }}>({base.review_count})</span>
              </span>
            )}
          </div>
        </div>
        {/* Read-only: only NexAround can hide or show a whole listing. */}
        <span
          className={`pill tone-${base.is_active ? 'green' : 'gray'}`}
          title={base.is_active ? '' : 'Contact NexAround to make your listing live again'}
        >
          {base.is_active ? 'Listing live' : 'Listing hidden'}
        </span>
      </div>

      <div className="xp-tabs">
        {TABS.map(([key, label]) => (
          <button key={key} className={`xp-tab ${tab === key ? 'active' : ''}`} onClick={() => setTab(key)}>
            {label}
          </button>
        ))}
      </div>

      <div className="xp-body">
        {tab === 'details' && (
          <div>
            <Section tone="teal" icon={CompassIcon} title="Business details" hint="Your name and what you offer.">
              <div className="form-group">
                <label className="form-label">Business name</label>
                <input
                  type="text" required className="form-input"
                  value={form.name || ''} onChange={(e) => patch({ name: e.target.value })}
                />
              </div>
              <div className="form-group">
                <label className="form-label">Description</label>
                <textarea
                  className="form-textarea" rows={5} value={form.description || ''}
                  placeholder="What you offer and what makes it worth booking"
                  onChange={(e) => patch({ description: e.target.value })}
                />
              </div>
            </Section>
            <Section tone="violet" icon={ImageIcon} title="Photos" hint="Photos of your business. The first is the main one.">
              <ImageUploader
                label={null}
                value={form.photo_urls || []}
                uploadEndpoint="/partner/upload"
                onChange={(urls) => patch({ photo_urls: urls })}
              />
            </Section>
          </div>
        )}

        {tab === 'location' && (
          <Section tone="rose" icon={MapPinIcon} title="Location" hint="Where travellers find you on the map.">
            <div className="form-grid-2">
              <div className="form-group">
                <label className="form-label">City</label>
                <input
                  type="text" className="form-input" placeholder="Trincomalee"
                  value={form.city || ''} onChange={(e) => patch({ city: e.target.value })}
                />
              </div>
              <div className="form-group">
                <label className="form-label">Country code</label>
                <input
                  type="text" maxLength={2} className="form-input" value={form.country_code || ''}
                  onChange={(e) => patch({ country_code: e.target.value.toUpperCase() })}
                />
              </div>
            </div>
            <LocationPicker
              mapId="partner-location-map"
              latitude={form.latitude ?? ''}
              longitude={form.longitude ?? ''}
              address={form.address || ''}
              searchEndpoint="/partner/place-search"
              onPick={(p) => {
                // The picker also offers a name and a Google place id. The name is
                // the vendor's to choose, and the place id is admin-only, so both
                // are dropped here rather than relied on being ignored downstream.
                const next = { ...p };
                delete next.name;
                delete next.google_place_id;
                patch(next);
              }}
            />
          </Section>
        )}

        {tab === 'contact' && (
          <div>
            <Section tone="green" icon={PhoneIcon} title="Direct contact" hint="Your email receives new enquiries and is not shown in the app.">
              <div className="form-grid-2">
                <div className="form-group">
                  <label className="form-label">Phone</label>
                  <input
                    type="text" className="form-input" placeholder="+94 77 123 4567"
                    value={form.contact_phone || ''} onChange={(e) => patch({ contact_phone: e.target.value })}
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">WhatsApp</label>
                  <input
                    type="text" className="form-input" placeholder="+94 77 123 4567"
                    value={form.contact_whatsapp || ''} onChange={(e) => patch({ contact_whatsapp: e.target.value })}
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">Email</label>
                  <input
                    type="email" className="form-input" placeholder="bookings@business.com"
                    value={form.contact_email || ''} onChange={(e) => patch({ contact_email: e.target.value })}
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">Website</label>
                  <input
                    type="text" className="form-input" placeholder="https://business.com"
                    value={form.website || ''} onChange={(e) => patch({ website: e.target.value })}
                  />
                </div>
              </div>
            </Section>
            <Section tone="blue" icon={GlobeIcon} title="Social" hint="A handle or a full URL both work.">
              <div className="form-grid-3">
                <div className="form-group">
                  <label className="form-label">Instagram</label>
                  <input
                    type="text" className="form-input" placeholder="@handle"
                    value={form.contact_instagram || ''} onChange={(e) => patch({ contact_instagram: e.target.value })}
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">Facebook</label>
                  <input
                    type="text" className="form-input" placeholder="facebook.com/…"
                    value={form.contact_facebook || ''} onChange={(e) => patch({ contact_facebook: e.target.value })}
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">X</label>
                  <input
                    type="text" className="form-input" placeholder="@handle"
                    value={form.contact_x || ''} onChange={(e) => patch({ contact_x: e.target.value })}
                  />
                </div>
              </div>
            </Section>
          </div>
        )}
      </div>

      <div className="xp-savebar">
        {dirty
          ? <span className="unsaved"><span className="dot dot-new" /> Unsaved changes</span>
          : <span>All changes saved</span>}
        <div style={{ display: 'flex', gap: 8 }}>
          {dirty && <button className="btn btn-ghost btn-sm" onClick={() => setForm(base)}>Discard</button>}
          <button className="btn btn-primary btn-sm" disabled={!dirty || saving} onClick={save}>
            {saving ? 'Saving…' : 'Save changes'}
          </button>
        </div>
      </div>

      <Toast toast={toast} />
    </div>
  );
}
