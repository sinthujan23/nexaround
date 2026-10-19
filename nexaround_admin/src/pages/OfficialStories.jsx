import { useState } from 'react';
import { useApi, apiPost, apiPut, apiDelete, mediaUrl } from '../api';
import { BookOpenIcon, PlusIcon, RefreshIcon, TrashIcon } from '../components/Icons';
import { Switch, Toast } from '../components/Kit';
import ImageUploader from '../components/ImageUploader';
import LocationPicker from '../components/LocationPicker';
import DescriptionEditor from '../components/DescriptionEditor';
import { COUNTRIES, getCountryByCode } from '../constants/countries';
import { useToast } from '../hooks';

// The categories a traveller can pick when posting a story in the app.
const CATEGORIES = [
  '💎 Hidden Gem',
  '🧭 Offbeat Place',
  '🤫 Local Secret',
  '🌅 Scenic Viewpoint',
  '🍔 Food Spot',
];

const EMPTY = {
  title: '',
  description: '',
  article_md: '',
  location_name: '',
  country: '',
  latitude: '',
  longitude: '',
  category: '🌅 Scenic Viewpoint',
  image_urls: [],
  is_public: true,
};

const FIELDS = Object.keys(EMPTY);
const pick = (story) => Object.fromEntries(FIELDS.map((k) => [k, story[k] ?? EMPTY[k]]));

const TZ = 'Asia/Colombo';
const formatDate = (value) =>
  new Date(value).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: TZ });

/**
 * Travel stories the team posts as the verified TravelByte account. In the app
 * they sit first in the Travel Stories row, and "Read the experience" on them
 * opens the long text written here.
 */
export default function OfficialStories() {
  const { data, error, refetch } = useApi('/admin/travel-stories');
  // null = nothing open, 'new' = a story being written, otherwise its id.
  const [openId, setOpenId] = useState(null);
  const [form, setForm] = useState(EMPTY);
  const [formBase, setFormBase] = useState(EMPTY);
  const [photosBusy, setPhotosBusy] = useState(false);
  const [saving, setSaving] = useState(false);
  const [toast, notify] = useToast();

  const stories = data || [];
  const open = openId && openId !== 'new' ? stories.find((s) => s.id === openId) : null;
  const isDirty = JSON.stringify(form) !== JSON.stringify(formBase);
  const patchForm = (patch) => setForm((f) => ({ ...f, ...patch }));

  const leave = () => !isDirty || confirm('Leave without saving your changes?');

  const openStory = (story) => {
    if (!leave()) return;
    const values = story ? pick(story) : EMPTY;
    setOpenId(story ? story.id : 'new');
    setForm(values);
    setFormBase(values);
  };

  const close = () => {
    if (!leave()) return;
    setOpenId(null);
  };

  // A place picked from the search fills the name and country; the map pin
  // and the coordinate boxes only move the pin.
  const pickPlace = (patch) => {
    const next = {};
    if (patch.latitude !== undefined) next.latitude = patch.latitude;
    if (patch.longitude !== undefined) next.longitude = patch.longitude;
    if (patch.name && !form.location_name) next.location_name = patch.name;
    const country = getCountryByCode(patch.country_code)?.name || patch.country_name;
    if (country) next.country = country;
    patchForm(next);
  };

  const missing = [
    !form.image_urls.length && 'a photo',
    !form.title.trim() && 'a title',
    !form.description.trim() && 'the short intro',
    !form.location_name.trim() && 'the place name',
    !form.country.trim() && 'the country',
    (form.latitude === '' || form.longitude === '') && 'the map pin',
  ].filter(Boolean);

  const save = async () => {
    if (missing.length) {
      notify(`Add ${missing.join(', ')} first.`, 'error');
      return;
    }
    setSaving(true);
    try {
      const body = { ...form, latitude: Number(form.latitude), longitude: Number(form.longitude) };
      const saved = openId === 'new'
        ? await apiPost('/admin/travel-stories', body)
        : await apiPut(`/admin/travel-stories/${openId}`, body);
      const values = pick(saved);
      setOpenId(saved.id);
      setForm(values);
      setFormBase(values);
      refetch();
      notify(openId === 'new' ? 'Story posted' : 'Changes saved');
    } catch (err) {
      notify(`Could not save: ${err.message}`, 'error');
    } finally {
      setSaving(false);
    }
  };

  const remove = async () => {
    if (!confirm('Delete this story with its likes and comments? To take it down for now, switch it to hidden instead.')) return;
    try {
      await apiDelete(`/admin/travel-stories/${openId}`);
      setOpenId(null);
      refetch();
      notify('Story deleted');
    } catch (err) {
      notify(`Could not delete: ${err.message}`, 'error');
    }
  };

  return (
    <div>
      <div className="xp-toolbar">
        <div className="xp-section-hint" style={{ margin: 0 }}>
          Posted as <strong>TravelByte</strong> with a blue tick, first in the app’s Travel Stories row.
        </div>
        <div className="xp-toolbar-right">
          <button className="btn btn-ghost btn-sm" onClick={refetch} title="Refresh">
            <RefreshIcon size={15} /> Refresh
          </button>
          <button className="btn btn-primary btn-sm" onClick={() => openStory(null)}>
            <PlusIcon size={14} /> New story
          </button>
        </div>
      </div>

      {error && <div className="login-error">{error}</div>}

      <div className={`xp-split ${openId ? 'has-selection' : ''}`}>
        <aside className="xp-pane xp-list-pane">
          <div className="xp-list-body">
            {!data && !error && <div className="loader" />}

            {data && stories.length === 0 && (
              <div className="xp-empty">
                <BookOpenIcon size={32} />
                <strong>No stories yet</strong>
                Post the first one with “New story”.
              </div>
            )}

            {stories.map((s) => (
              <button
                key={s.id}
                className={`xp-row ${openId === s.id ? 'active' : ''}`}
                onClick={() => openStory(s)}
              >
                <div className="pkg-thumb">
                  {s.image_urls?.[0] ? <img src={mediaUrl(s.image_urls[0])} alt="" /> : <BookOpenIcon size={18} />}
                </div>
                <div className="xp-row-main">
                  <div className="xp-row-title">{s.location_name}</div>
                  <div className="xp-row-sub">{s.country} · {s.title}</div>
                  <div className="xp-row-sub">♥ {s.likes_count} · 💬 {s.comments_count} · {formatDate(s.created_at)}</div>
                </div>
                <span className={`dot dot-${s.is_public ? 'live' : 'hidden'}`} title={s.is_public ? 'Published' : 'Hidden'} />
              </button>
            ))}
          </div>
        </aside>

        <section className="xp-pane xp-detail-pane">
          {!openId && (
            <div className="xp-empty">
              <BookOpenIcon size={36} />
              <strong>Select a story</strong>
              Or write a new one: photos, the place, a short intro for the card, and the full experience.
            </div>
          )}

          {openId && (
            <>
              <div className="xp-detail-head">
                <div style={{ flex: 1, minWidth: 0 }}>
                  <button className="xp-back" onClick={close}>← All stories</button>
                  <div className="xp-detail-title">{openId === 'new' ? 'New story' : (open?.location_name || form.location_name)}</div>
                  {open && (
                    <div className="xp-detail-sub">
                      Posted {formatDate(open.created_at)} · ♥ {open.likes_count} · 💬 {open.comments_count}
                    </div>
                  )}
                </div>
                <Switch
                  checked={form.is_public}
                  onChange={(v) => patchForm({ is_public: v })}
                  label={form.is_public ? 'Published' : 'Hidden'}
                />
              </div>

              <div className="xp-body">
                <div className="xp-section">
                  <div className="xp-section-title">Photos</div>
                  <div className="xp-section-hint">The first photo is the cover. Travellers swipe through the rest.</div>
                  <ImageUploader
                    key={openId}
                    label="Photos *"
                    value={form.image_urls}
                    onUploadingChange={setPhotosBusy}
                    onChange={(urls) => patchForm({ image_urls: urls })}
                  />
                </div>

                <div className="xp-section">
                  <div className="xp-section-title">Place</div>
                  <div className="xp-section-hint">Search on Google, then check the pin. The country fills in from the place.</div>
                  <LocationPicker
                    key={openId}
                    mapId="official-story-map"
                    latitude={form.latitude}
                    longitude={form.longitude}
                    showAddress={false}
                    searchLabel="Find the place on Google"
                    searchPlaceholder="e.g. Furong Ancient Town, Hunan"
                    onPick={pickPlace}
                  />
                  <div className="form-grid-2">
                    <div className="form-group">
                      <label className="form-label">Place name *</label>
                      <input
                        type="text" className="form-input" value={form.location_name} maxLength={255}
                        placeholder="Furong Ancient Town"
                        onChange={(e) => patchForm({ location_name: e.target.value })}
                      />
                    </div>
                    <div className="form-group">
                      <label className="form-label">Country *</label>
                      <input
                        type="text" className="form-input" value={form.country} maxLength={100}
                        list="official-story-countries" placeholder="China"
                        onChange={(e) => patchForm({ country: e.target.value })}
                      />
                      <datalist id="official-story-countries">
                        {COUNTRIES.map((c) => <option key={c.code} value={c.name} />)}
                      </datalist>
                    </div>
                  </div>
                </div>

                <div className="xp-section">
                  <div className="xp-section-title">On the story card</div>
                  <div className="form-grid-2">
                    <div className="form-group">
                      <label className="form-label">Title *</label>
                      <input
                        type="text" className="form-input" value={form.title} maxLength={200}
                        placeholder="A Magical Waterfall Village Straight Out of a Fairytale"
                        onChange={(e) => patchForm({ title: e.target.value })}
                      />
                    </div>
                    <div className="form-group">
                      <label className="form-label">Category</label>
                      <select
                        className="form-input" value={form.category}
                        onChange={(e) => patchForm({ category: e.target.value })}
                      >
                        {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
                      </select>
                    </div>
                  </div>
                  <div className="form-group">
                    <label className="form-label">Short intro * <span className="muted">({form.description.length}/1000)</span></label>
                    <textarea
                      className="form-textarea" rows={4} value={form.description} maxLength={1000}
                      placeholder="A paragraph or two that makes people want to read on"
                      onChange={(e) => patchForm({ description: e.target.value })}
                    />
                  </div>
                </div>

                <div className="xp-section">
                  <div className="xp-section-title">The experience</div>
                  <div className="xp-section-hint">
                    Opens when a traveller taps “Read the experience”. Start each section with a Heading.
                  </div>
                  <DescriptionEditor
                    rows={18}
                    value={form.article_md}
                    placeholder="Heading for each section, then the text under it"
                    onChange={(v) => patchForm({ article_md: v })}
                  />
                </div>

                {openId !== 'new' && (
                  <div className="xp-section">
                    <div className="xp-section-title">Delete</div>
                    <div className="xp-section-hint">Removes the story, its likes and comments for good. Hiding keeps them.</div>
                    <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
                      <button className="btn btn-danger-ghost btn-sm" onClick={remove}>
                        <TrashIcon size={14} /> Delete story
                      </button>
                    </div>
                  </div>
                )}
              </div>

              <div className="xp-savebar">
                {isDirty
                  ? <span className="unsaved"><span className="dot dot-new" /> Unsaved changes</span>
                  : <span>{openId === 'new' ? 'Not posted yet' : 'All changes saved'}</span>}
                <div style={{ display: 'flex', gap: 8 }}>
                  {isDirty && openId !== 'new' && (
                    <button className="btn btn-ghost btn-sm" onClick={() => setForm(formBase)}>Discard</button>
                  )}
                  <button className="btn btn-primary btn-sm" disabled={!isDirty || saving || photosBusy} onClick={save}>
                    {photosBusy ? 'Uploading photos…' : saving ? 'Saving…' : openId === 'new' ? 'Post story' : 'Save changes'}
                  </button>
                </div>
              </div>
            </>
          )}
        </section>
      </div>

      <Toast toast={toast} />
    </div>
  );
}
