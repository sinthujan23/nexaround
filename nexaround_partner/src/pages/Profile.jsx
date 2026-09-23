import { useEffect, useState } from 'react';
import { apiGet, apiPut } from '../api';
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
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    apiGet('/partner/profile')
      .then(setForm)
      .catch((err) => setError(err.message || 'Could not load your profile.'));
  }, []);

  const patch = (p) => { setForm((prev) => ({ ...prev, ...p })); setSaved(false); };

  const save = async (e) => {
    e.preventDefault();
    if (form.latitude === '' || form.latitude == null) {
      alert('Set your location on the map first.');
      return;
    }
    setSaving(true);
    setError('');
    try {
      const updated = await apiPut('/partner/profile', {
        ...form,
        latitude: Number(form.latitude),
        longitude: Number(form.longitude),
      });
      setForm(updated);
      setSaved(true);
      // The sidebar shows the business name, so a rename must reach it.
      if (onSaved) {
        onSaved((prev) => (prev ? { ...prev, vendor_name: updated.name } : prev));
      }
    } catch (err) {
      setError(err.message || 'Could not save.');
    } finally {
      setSaving(false);
    }
  };

  if (error && !form) return <div className="login-error">{error}</div>;
  if (!form) return <div className="loader" />;

  return (
    <form className="card" style={{ padding: '24px' }} onSubmit={save}>
      <div className="card-header">
        <div className="card-title">Your business</div>
        {form.rating != null && (
          <span className="badge badge-ghost">
            {form.rating} &#9733; &middot; {form.review_count} reviews
          </span>
        )}
      </div>

      {error && <div className="login-error">{error}</div>}
      {saved && (
        <div className="badge badge-green" style={{ marginBottom: '12px' }}>
          Saved. Travellers see this straight away.
        </div>
      )}

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
          className="form-textarea" rows={4}
          value={form.description || ''} onChange={(e) => patch({ description: e.target.value })}
        />
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

      <div className="form-grid-2">
        <div className="form-group">
          <label className="form-label">City</label>
          <input
            type="text" className="form-input"
            value={form.city || ''} onChange={(e) => patch({ city: e.target.value })}
          />
        </div>
        <div className="form-group">
          <label className="form-label">Country code (2 letters)</label>
          <input
            type="text" maxLength={2} className="form-input"
            value={form.country_code || ''}
            onChange={(e) => patch({ country_code: e.target.value.toUpperCase() })}
          />
        </div>
      </div>

      <div className="form-grid-2">
        <div className="form-group">
          <label className="form-label">Phone</label>
          <input
            type="text" className="form-input"
            value={form.contact_phone || ''} onChange={(e) => patch({ contact_phone: e.target.value })}
          />
        </div>
        <div className="form-group">
          <label className="form-label">WhatsApp</label>
          <input
            type="text" className="form-input"
            value={form.contact_whatsapp || ''} onChange={(e) => patch({ contact_whatsapp: e.target.value })}
          />
        </div>
      </div>

      <div className="form-grid-2">
        <div className="form-group">
          <label className="form-label">Email (for enquiries &mdash; not shown in the app)</label>
          <input
            type="email" className="form-input"
            value={form.contact_email || ''} onChange={(e) => patch({ contact_email: e.target.value })}
          />
        </div>
        <div className="form-group">
          <label className="form-label">Website</label>
          <input
            type="text" className="form-input"
            value={form.website || ''} onChange={(e) => patch({ website: e.target.value })}
          />
        </div>
      </div>

      <div className="form-grid-2">
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
            type="text" className="form-input" placeholder="facebook.com/..."
            value={form.contact_facebook || ''} onChange={(e) => patch({ contact_facebook: e.target.value })}
          />
        </div>
      </div>

      <div className="form-group">
        <label className="form-label">X</label>
        <input
          type="text" className="form-input" placeholder="@handle"
          value={form.contact_x || ''} onChange={(e) => patch({ contact_x: e.target.value })}
        />
      </div>

      <ImageUploader
        label="Photos of your business"
        value={form.photo_urls || []}
        uploadEndpoint="/partner/upload"
        onChange={(urls) => patch({ photo_urls: urls })}
      />

      <div style={{ display: 'flex', gap: '10px', marginTop: '8px' }}>
        <button type="submit" className="btn btn-primary" disabled={saving}>
          {saving ? 'Saving…' : 'Save changes'}
        </button>
      </div>
    </form>
  );
}
