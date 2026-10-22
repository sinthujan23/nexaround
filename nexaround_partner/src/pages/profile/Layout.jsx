import { useEffect, useState } from 'react';
import { Outlet } from 'react-router-dom';
import { apiGet, apiPut, mediaUrl } from '../../api';
import { useUnsavedGuard } from '../../hooks';
import { useToast } from '../../toast';
import { StarIcon } from '../../components/Icons';
import { ErrorBanner, Loader, StatusPill } from '../../components/Lists';
import { SaveBar } from '../../components/Forms';
import TabNav from '../../components/TabNav';
import ReviewNotice from '../../components/ReviewNotice';

const TABS = [
  { to: '/profile/details', label: 'Details' },
  { to: '/profile/location', label: 'Location' },
  { to: '/profile/contact', label: 'Contact & social' },
];

/**
 * The vendor's own record.
 *
 * Mirrors the admin vendor form minus everything the platform reserves:
 * Active/Hidden, rating, review count, internal notes and sort order have no
 * inputs here, and where the business is (address, map pin, website) and
 * how travellers reach it are shown read-only. That is presentation only —
 * the server drops those fields even if a crafted request carries them.
 * What the vendor can change waits for NexAround's review before travellers
 * see it.
 *
 * Each tab is its own page, but they are one form: this layout owns the state
 * and the Save bar, and the tabs read it through the router's outlet context.
 * Moving between tabs therefore never loses an edit; leaving /profile with
 * unsaved changes asks first.
 */
export default function ProfileLayout() {
  const notify = useToast();
  const [form, setForm] = useState(null);
  const [base, setBase] = useState(null);
  const [saving, setSaving] = useState(false);
  // True while the Details tab's photo uploader is uploading; saving then would leave those photos out.
  const [photosBusy, setPhotosBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    apiGet('/partner/profile')
      .then((profile) => { setForm(profile); setBase(profile); })
      .catch((err) => setError(err.message || 'Could not load your profile.'));
  }, []);

  const dirty = Boolean(form) && JSON.stringify(form) !== JSON.stringify(base);
  // Switching tab unmounts the uploader and drops its result, so it is held too.
  useUnsavedGuard(dirty || photosBusy, {
    allow: (next) => !photosBusy && next.pathname.startsWith('/profile'),
  });

  const patch = (p) => setForm((prev) => ({ ...prev, ...p }));

  const save = async () => {
    if (photosBusy) {
      notify('Photos are still uploading. Wait for them to finish, then save.', 'error');
      return;
    }
    setSaving(true);
    try {
      const updated = await apiPut('/partner/profile', {
        name: form.name,
        description: form.description,
        contact_email: form.contact_email,
        logo_url: form.logo_url,
        photo_urls: form.photo_urls,
      });
      setForm(updated);
      setBase(updated);
      // The sidebar keeps the live name until NexAround approves a new one.
      notify(updated.review_status === 'pending'
        ? 'Sent for review. Travellers see your current profile until NexAround approves it.'
        : 'Saved.');
    } catch (err) {
      notify(err.message || 'Could not save.', 'error');
    } finally {
      setSaving(false);
    }
  };

  if (error && !form) return <ErrorBanner>{error}</ErrorBanner>;
  if (!form) return <Loader />;

  const photo = base.logo_url || base.photo_urls?.[0];

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
        <StatusPill
          tone={base.is_active ? 'green' : 'gray'}
          title={base.is_active ? '' : 'Contact NexAround to make your listing live again'}
        >
          {base.is_active ? 'Listing live' : 'Listing hidden'}
        </StatusPill>
      </div>

      <TabNav items={TABS} />

      <div className="xp-body">
        <ReviewNotice item={base} what="profile" />
        <Outlet context={{ form, patch, setPhotosBusy }} />
      </div>

      <SaveBar dirty={dirty} saving={saving} busy={photosBusy} onSave={save} onDiscard={() => setForm(base)} />
    </div>
  );
}
