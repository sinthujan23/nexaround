import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { apiDelete, apiGet, apiPost, apiPut } from '../api';
import { useConfirm } from '../confirm';
import { useUnsavedGuard } from '../hooks';
import { useToast } from '../toast';
import {
  TrashIcon, TicketIcon, DollarIcon, ImageIcon, ClipboardCheckIcon, MapPinIcon, ClockIcon,
} from '../components/Icons';
import { Switch, Section } from '../components/Kit';
import { EmptyState, Loader } from '../components/Lists';
import { FieldGrid, SaveBar, SelectField, TextArea, TextField, Field } from '../components/Forms';
import LocationPicker from '../components/LocationPicker';
import ImageUploader from '../components/ImageUploader';
import AvailabilityCalendar from '../components/AvailabilityCalendar';
import DescriptionEditor from '../components/DescriptionEditor';
import { CATEGORIES, PRICE_BASES, bookingWindowOptions } from '../format';
import {
  EMPTY_PACKAGE, arrayToLines, fromPackage, linesToArray, toPayload,
} from './packageForm';

/** /packages/new and /packages/:packageId. Keyed so one never inherits the other's form. */
export default function PackageEditor() {
  const { packageId } = useParams();
  return <PackageForm key={packageId || 'new'} packageId={packageId} />;
}

function PackageForm({ packageId }) {
  const isNew = !packageId;
  const navigate = useNavigate();
  const notify = useToast();
  const confirm = useConfirm();

  const [form, setForm] = useState(isNew ? EMPTY_PACKAGE : null);
  const [base, setBase] = useState(isNew ? EMPTY_PACKAGE : null);
  const [loadError, setLoadError] = useState('');
  const [saving, setSaving] = useState(false);
  // True while the photo uploader is uploading; saving then would leave those photos out.
  const [photosBusy, setPhotosBusy] = useState(false);

  useEffect(() => {
    if (isNew) return;
    apiGet(`/partner/packages/${packageId}`)
      .then((pkg) => { const f = fromPackage(pkg); setForm(f); setBase(f); })
      .catch((err) => setLoadError(err.message || 'Could not load this package.'));
  }, [isNew, packageId]);

  const dirty = form && JSON.stringify(form) !== JSON.stringify(base);
  const guard = useUnsavedGuard(Boolean(dirty) || photosBusy);

  const patch = (p) => setForm((prev) => ({ ...prev, ...p }));
  const backToList = () => { guard.release(); navigate('/packages'); };

  const save = async (e) => {
    e.preventDefault();
    if (photosBusy) {
      notify('Photos are still uploading. Wait for them to finish, then save.', 'error');
      return;
    }
    if (!form.uses_vendor_location && (form.latitude === '' || form.latitude == null)) {
      notify('Pick the meeting point on the map, or use your business address.', 'error');
      return;
    }
    setSaving(true);
    try {
      if (isNew) await apiPost('/partner/packages', toPayload(form));
      else await apiPut(`/partner/packages/${packageId}`, toPayload(form));
      notify(isNew ? 'Package created' : 'Package saved');
      backToList();
    } catch (err) {
      notify(`Could not save: ${err.message}`, 'error');
      setSaving(false);
    }
  };

  const remove = async () => {
    const ok = await confirm({
      title: `Delete "${form.title}"?`,
      message: 'Travellers will no longer see it. This cannot be undone.',
      confirmLabel: 'Delete package',
      danger: true,
    });
    if (!ok) return;
    try {
      await apiDelete(`/partner/packages/${packageId}`);
      notify('Package deleted');
      backToList();
    } catch (err) {
      notify(`Could not delete: ${err.message}`, 'error');
    }
  };

  if (loadError) {
    return (
      <EmptyState card pad={48} icon={TicketIcon} title="Package not found">
        {loadError}
        <div style={{ marginTop: 12 }}>
          <Link className="btn btn-ghost btn-sm" to="/packages">Back to my packages</Link>
        </div>
      </EmptyState>
    );
  }
  if (!form) return <Loader />;

  return (
    <form className="editor" onSubmit={save}>
      <Section tone="teal" icon={TicketIcon} title="Basic details" hint="What travellers see first.">
        <TextField
          label="Title *" required autoFocus={isNew} value={form.title}
          placeholder="Pigeon Island snorkelling & boat safari"
          onChange={(v) => patch({ title: v })}
        />
        <SelectField
          label="Category" value={form.category || 'other'} options={CATEGORIES}
          onChange={(v) => patch({ category: v })}
        />
        <TextField
          label="Summary" maxLength={500} value={form.summary}
          placeholder="One line for the card in the app"
          onChange={(v) => patch({ summary: v })}
        />
        <Field label="Description" hint="Select text and use the buttons to add headings, bold and lists. Preview shows what travellers will see.">
          <DescriptionEditor
            value={form.description}
            placeholder="Itinerary, what to bring, safety notes…"
            onChange={(v) => patch({ description: v })}
          />
        </Field>
      </Section>

      <Section tone="amber" icon={DollarIcon} title="Price & capacity" hint="Leave the price empty to show “On request”.">
        <FieldGrid cols={3}>
          <TextField
            label="Price" type="number" step="0.01" min="0" placeholder="7500"
            value={form.price_amount} onChange={(v) => patch({ price_amount: v })}
          />
          <TextField
            label="Currency" maxLength={10} value={form.price_currency || ''}
            onChange={(v) => patch({ price_currency: v.toUpperCase() })}
          />
          <SelectField
            label="Basis" value={form.price_basis || 'per_person'} options={PRICE_BASES}
            onChange={(v) => patch({ price_basis: v })}
          />
        </FieldGrid>
        <FieldGrid cols={3}>
          <TextField
            label="Duration (minutes)" type="number" min="0" placeholder="180"
            value={form.duration_minutes} onChange={(v) => patch({ duration_minutes: v })}
          />
          <TextField
            label="Max participants" type="number" min="1" placeholder="8"
            value={form.max_participants} onChange={(v) => patch({ max_participants: v })}
          />
          <SelectField
            label="Bookable" value={form.booking_window_days ?? ''}
            title="How far ahead travellers can pick a date"
            options={bookingWindowOptions(form.booking_window_days)}
            onChange={(v) => patch({ booking_window_days: v })}
          />
        </FieldGrid>
      </Section>

      <Section
        tone="rose" icon={ClockIcon} title="Availability"
        hint="Available every day unless you block dates here, for example when you are on leave or fully booked. Travellers cannot pick a blocked day."
      >
        <AvailabilityCalendar
          value={form.unavailable_ranges}
          maxDays={Number(form.booking_window_days) || 365}
          onChange={(ranges) => patch({ unavailable_ranges: ranges })}
        />
      </Section>

      <Section tone="violet" icon={ImageIcon} title="Photos" hint="The first photo is the one shown on the card.">
        <ImageUploader
          label={null}
          value={form.photo_urls}
          uploadEndpoint="/partner/upload"
          onUploadingChange={setPhotosBusy}
          onChange={(urls) => patch({ photo_urls: urls })}
        />
      </Section>

      <Section tone="blue" icon={ClipboardCheckIcon} title="Included & languages" hint="One item per line.">
        <FieldGrid cols={2}>
          <TextArea
            label="What’s included" value={arrayToLines(form.inclusions)}
            placeholder={'Snorkelling gear\nLife jackets\nBottled water'}
            onChange={(v) => patch({ inclusions: linesToArray(v) })}
          />
          <TextArea
            label="Languages" value={arrayToLines(form.languages)}
            placeholder={'English\nTamil\nSinhala'}
            onChange={(v) => patch({ languages: linesToArray(v) })}
          />
        </FieldGrid>
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
          <Field>
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
          </Field>
        )}
      </Section>

      <SaveBar
        submit
        dirty={dirty}
        saving={saving}
        busy={photosBusy}
        saveLabel={isNew ? 'Create package' : 'Save package'}
        left={(
          <Switch
            checked={form.is_active}
            onChange={(v) => patch({ is_active: v })}
            label={form.is_active ? 'Show in the app' : 'Hidden (draft)'}
          />
        )}
        extra={(
          <>
            {!isNew && (
              <button type="button" className="icon-btn danger" title="Delete package" onClick={remove}>
                <TrashIcon size={15} />
              </button>
            )}
            <Link className="btn btn-ghost btn-sm" to="/packages">Cancel</Link>
          </>
        )}
      />
    </form>
  );
}
