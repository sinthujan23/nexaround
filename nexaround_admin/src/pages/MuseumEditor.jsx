import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { apiDelete, apiGet, apiPost, apiPut, apiUploadFile, mediaUrl } from '../api';
import { Badge, Drawer, PageError, PageLoading, Switch, Toast } from '../components/Kit';
import { ArrowDownIcon, ArrowUpIcon, EditIcon, MuseumIcon, PlusIcon, TrashIcon } from '../components/Icons';
import MuseumPreview from '../components/MuseumPreview';
import { useToast } from '../hooks';
import { COUNTRIES } from '../constants/countries';
import { DURATIONS, TOUR_LABELS, renumberTours, tourOrder } from '../museums';
import { isCreator } from '../session';

let keySeed = 0;
const newKey = () => `new-${++keySeed}`;

const ITEM_TEXT = ['building', 'room_gallery', 'must_see_item', 'artist', 'category', 'description'];

/** The editor's copy of a museum: numbers as typed text, items with a key. */
function toForm(detail) {
  const items = detail.items.map((item) => ({
    key: item.id, id: item.id,
    ...Object.fromEntries(ITEM_TEXT.map((k) => [k, item[k] || ''])),
    ...Object.fromEntries(DURATIONS.flatMap((d) => [[`included_${d}`, item[`included_${d}`]], [`stop_${d}`, item[`stop_${d}`]]])),
  }));
  return {
    name: detail.name, city: detail.city, country: detail.country,
    annual_visitors: detail.annual_visitors ?? '', rank: detail.rank ?? '',
    opening_hours: detail.opening_hours || '', website: detail.website || '',
    // Stops as the app orders them, numbered 1..n, so moving and adding is plain.
    items: renumberTours(items),
  };
}

/** What is wrong with the museum's own fields, by field. */
function museumErrors(form) {
  const errors = {};
  if (!form.name.trim()) errors.name = 'Add the museum’s name.';
  if (!form.city.trim()) errors.city = 'Add the city.';
  if (!form.country.trim()) errors.country = 'Add the country.';
  if (String(form.annual_visitors).trim() && !/^\d+$/.test(String(form.annual_visitors).trim())) {
    errors.annual_visitors = 'Whole number only, e.g. 3846375.';
  }
  if (String(form.rank).trim() && !/^[1-9]\d*$/.test(String(form.rank).trim())) {
    errors.rank = 'A whole number from 1.';
  }
  if (form.website.trim() && !/^https?:\/\/\S+\.\S+/.test(form.website.trim())) {
    errors.website = 'A full web address, starting with https://';
  }
  return errors;
}

const MUSEUM_FIELD_IDS = {
  name: 'mu-name', city: 'mu-city', country: 'mu-country', annual_visitors: 'mu-visitors',
  rank: 'mu-rank', opening_hours: 'mu-hours', website: 'mu-website',
};

/** What is wrong with an item, by field. */
function itemErrors(item) {
  const errors = {};
  if (!item.must_see_item.trim()) errors.must_see_item = 'Add the item’s name.';
  if (!item.category.trim()) errors.category = 'Add a category, e.g. Renaissance Painting.';
  if (!item.building.trim()) errors.building = 'Add the building or wing.';
  if (!item.room_gallery.trim()) errors.room_gallery = 'Add the room or gallery.';
  return errors;
}

const ITEM_FIELD_IDS = {
  must_see_item: 'mi-name', category: 'mi-category', building: 'mi-building', room_gallery: 'mi-room',
};

function FieldError({ message }) {
  return message ? <div className="form-field-error" role="alert">{message}</div> : null;
}

const payload = (form) => ({
  name: form.name.trim(),
  city: form.city.trim(),
  country: form.country.trim(),
  annual_visitors: String(form.annual_visitors).trim() ? Number(form.annual_visitors) : null,
  rank: String(form.rank).trim() ? Number(form.rank) : null,
  opening_hours: form.opening_hours.trim() || null,
  website: form.website.trim() || null,
  items: form.items.map((item) => ({
    id: item.id || null,
    ...Object.fromEntries(ITEM_TEXT.map((k) => [k, item[k].trim() || null])),
    ...Object.fromEntries(DURATIONS.flatMap((d) => [[`included_${d}`, item[`included_${d}`]], [`stop_${d}`, item[`stop_${d}`]]])),
  })),
});

/** The tours an item is part of, as small labels. */
function TourChips({ item }) {
  const on = DURATIONS.filter((d) => item[`included_${d}`]);
  if (!on.length) return <Badge tone="yellow">In no tour</Badge>;
  return on.map((d) => <Badge key={d} tone="ghost">{TOUR_LABELS[d]}</Badge>);
}

/**
 * One museum, entered the way the app shows it: the card and guide header,
 * then the must-see items. "All items" is the museum's full list; each tour
 * tab is that tour's walking order, which can differ from the full list.
 */
export default function MuseumEditor() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const id = params.get('id');
  const isAdmin = !isCreator();

  const [detail, setDetail] = useState(null);
  const [form, setForm] = useState(null);
  const [base, setBase] = useState(null);
  const [loadError, setLoadError] = useState(null);
  const [busy, setBusy] = useState('');
  const [checked, setChecked] = useState(false);
  const [tab, setTab] = useState('all');
  const [editing, setEditing] = useState(null); // an item in the drawer
  const [toast, notify] = useToast(5000);
  const photoInput = useRef(null);

  const apply = (next) => {
    const f = toForm(next);
    setDetail(next);
    setForm(f);
    setBase(f);
  };

  const load = () => {
    setLoadError(null);
    apiGet(`/admin/museums/${id}`).then(apply).catch(setLoadError);
  };
  useEffect(() => {
    if (!id) { navigate('/museums', { replace: true }); return; }
    let current = true;
    apiGet(`/admin/museums/${id}`)
      .then((next) => { if (current) apply(next); })
      .catch((err) => { if (current) setLoadError(err); });
    return () => { current = false; };
  }, [id, navigate]);

  const dirty = useMemo(() => form && base && JSON.stringify(form) !== JSON.stringify(base), [form, base]);
  const errors = checked && form ? museumErrors(form) : {};
  const categories = detail?.categories || [];
  const buildings = useMemo(
    () => [...new Set((form?.items || []).map((i) => i.building.trim()).filter(Boolean))],
    [form],
  );

  if (loadError && !detail) return <PageError error={loadError} onRetry={load} />;
  if (!form) return <PageLoading />;

  const patch = (changes) => setForm({ ...form, ...changes });
  const setItems = (items) => setForm({ ...form, items: renumberTours(items) });

  // ── Full list ──
  const moveInList = (index, by) => {
    const items = [...form.items];
    [items[index], items[index + by]] = [items[index + by], items[index]];
    setForm({ ...form, items }); // tours keep their own order
  };
  const removeItem = (item) => {
    if (!confirm(`Remove “${item.must_see_item}” from this museum? It leaves every tour too.`)) return;
    setItems(form.items.filter((i) => i.key !== item.key));
  };

  // ── One tour ──
  const moveInTour = (d, index, by) => {
    const order = tourOrder(form.items, d);
    [order[index], order[index + by]] = [order[index + by], order[index]];
    const stops = new Map(order.map((item, i) => [item.key, i + 1]));
    setForm({ ...form, items: form.items.map((item) => (stops.has(item.key) ? { ...item, [`stop_${d}`]: stops.get(item.key) } : item)) });
  };
  const leaveTour = (d, item) => setItems(form.items.map((i) => (
    i.key === item.key ? { ...i, [`included_${d}`]: false, [`stop_${d}`]: null } : i
  )));
  const followList = (d) => setItems(form.items.map((i) => ({ ...i, [`stop_${d}`]: null })));

  // ── Item drawer ──
  const openNew = () => setEditing({
    key: newKey(), id: null, isNew: true, checked: false,
    ...Object.fromEntries(ITEM_TEXT.map((k) => [k, ''])),
    ...Object.fromEntries(DURATIONS.flatMap((d) => [[`included_${d}`, tab === d], [`stop_${d}`, null]])),
  });
  const saveItem = (e) => {
    e?.preventDefault();
    const problems = itemErrors(editing);
    const first = Object.keys(ITEM_FIELD_IDS).find((k) => problems[k]);
    if (first) {
      setEditing({ ...editing, checked: true });
      document.getElementById(ITEM_FIELD_IDS[first])?.focus();
      return;
    }
    const { isNew, ...item } = editing;
    delete item.checked;
    const before = form.items.find((i) => i.key === item.key);
    // Joining a tour puts the item at that tour's end.
    DURATIONS.forEach((d) => {
      const joins = item[`included_${d}`] && !(before && before[`included_${d}`]);
      if (joins) item[`stop_${d}`] = tourOrder(form.items, d).length + 1;
      if (!item[`included_${d}`]) item[`stop_${d}`] = null;
    });
    setItems(isNew ? [...form.items, item] : form.items.map((i) => (i.key === item.key ? item : i)));
    setEditing(null);
  };

  // ── Saving ──
  const save = async () => {
    const problems = museumErrors(form);
    const first = Object.keys(MUSEUM_FIELD_IDS).find((k) => problems[k]);
    if (first) {
      setChecked(true);
      document.getElementById(MUSEUM_FIELD_IDS[first])?.focus();
      return;
    }
    setBusy('save');
    try {
      apply(await apiPut(`/admin/museums/${id}`, payload(form)));
      setChecked(false);
      notify(detail.is_hidden ? 'Saved. It is still hidden from the app.' : 'Saved. The app shows it now.');
    } catch (err) {
      notify(err.message || 'Could not save.', 'error');
    } finally {
      setBusy('');
    }
  };

  const uploadPhoto = async (file) => {
    if (!file) return;
    setBusy('photo');
    try {
      const next = await apiUploadFile(`/admin/museums/${id}/photo`, file);
      // Only the photo changed on the server; anything typed stays.
      setDetail(next);
      notify('Photo saved');
    } catch (err) {
      notify(err.message || 'Could not upload the photo.', 'error');
    } finally {
      setBusy('');
      if (photoInput.current) photoInput.current.value = '';
    }
  };

  const setHidden = async (hidden) => {
    if (!hidden && dirty) {
      notify('Save your changes first, then switch it on.', 'error');
      return;
    }
    setBusy('hide');
    try {
      setDetail(await apiPost(`/admin/museums/${id}/visibility`, { hidden }));
      notify(hidden ? 'Hidden from the app' : 'Now in the app');
    } catch (err) {
      notify(err.message || 'Could not change it.', 'error');
    } finally {
      setBusy('');
    }
  };

  const remove = async () => {
    if (!confirm(`Delete ${detail.name} and all its must-see items for good?`)) return;
    setBusy('delete');
    try {
      await apiDelete(`/admin/museums/${id}`);
      navigate('/museums', { replace: true });
    } catch (err) {
      notify(err.message || 'Could not delete it.', 'error');
      setBusy('');
    }
  };

  const back = () => {
    if (dirty && !confirm('Leave without saving your changes?')) return;
    navigate('/museums');
  };

  const listRows = tab === 'all'
    ? form.items.map((item, i) => ({ item, number: i + 1 }))
    : tourOrder(form.items, tab).map((item, i) => ({ item, number: i + 1 }));
  const inTour = (d) => form.items.filter((i) => i[`included_${d}`]).length;
  const itemErr = editing?.checked ? itemErrors(editing) : {};

  return (
    <div className="cte">
      <div className="cte-head">
        <button type="button" className="xp-back" onClick={back}>← All museums</button>
        <div className="cte-title-row">
          <div className="cte-title">{form.name || 'Museum'}</div>
          <Badge tone={detail.is_hidden ? 'yellow' : 'green'}>{detail.is_hidden ? 'Hidden' : 'In the app'}</Badge>
        </div>
        <div className="xp-detail-sub">
          {form.items.length} must-see item{form.items.length === 1 ? '' : 's'}
          {DURATIONS.filter(inTour).map((d) => ` · ${TOUR_LABELS[d]}: ${inTour(d)}`).join('')}
        </div>
      </div>

      {detail.is_hidden && (
        <div className="cte-banner">
          Hidden from the app. Add the photo and must-see items, save, then switch it on at the bottom of the page.
        </div>
      )}

      <div className="cte-grid">
        <div className="cte-form">
          <section className="cte-card">
            <div className="xp-section-title">Museum card</div>
            <div className="xp-section-hint">What the app’s museum list and the top of the guide show.</div>
            <div className="form-group">
              <label className="form-label">Photo</label>
              <div className="cte-photo">
                <div className="cte-photo-box">
                  {detail.image_url ? <img src={mediaUrl(detail.image_url)} alt="" /> : <MuseumIcon size={22} />}
                </div>
                <div className="cte-photo-actions">
                  <button type="button" className="btn btn-ghost btn-sm" disabled={!!busy} onClick={() => photoInput.current?.click()}>
                    {busy === 'photo' ? 'Uploading…' : detail.image_url ? 'Change photo' : 'Upload photo'}
                  </button>
                  <span className="muted" style={{ fontSize: 12 }}>A wide photo of the building. Saved at once.</span>
                </div>
                <input
                  ref={photoInput} type="file" accept="image/jpeg,image/png,image/webp" hidden
                  onChange={(e) => uploadPhoto(e.target.files?.[0])}
                />
              </div>
            </div>
            <div className="form-group">
              <label className="form-label" htmlFor="mu-name">Museum name *</label>
              <input id="mu-name" className="form-input" maxLength={255} value={form.name}
                aria-invalid={!!errors.name || undefined} onChange={(e) => patch({ name: e.target.value })} />
              <FieldError message={errors.name} />
            </div>
            <div className="form-grid-2">
              <div className="form-group">
                <label className="form-label" htmlFor="mu-city">City *</label>
                <input id="mu-city" className="form-input" maxLength={120} value={form.city}
                  aria-invalid={!!errors.city || undefined} onChange={(e) => patch({ city: e.target.value })} />
                <FieldError message={errors.city} />
              </div>
              <div className="form-group">
                <label className="form-label" htmlFor="mu-country">Country *</label>
                <input id="mu-country" className="form-input" maxLength={120} value={form.country} list="mu-countries"
                  aria-invalid={!!errors.country || undefined} onChange={(e) => patch({ country: e.target.value })} />
                <FieldError message={errors.country} />
              </div>
            </div>
            <datalist id="mu-countries">{COUNTRIES.map((c) => <option key={c.code} value={c.name} />)}</datalist>
            <div className="form-grid-2">
              <div className="form-group">
                <label className="form-label" htmlFor="mu-visitors">Visitors per year</label>
                <input id="mu-visitors" className="form-input" inputMode="numeric" placeholder="e.g. 3846375" value={form.annual_visitors}
                  aria-invalid={!!errors.annual_visitors || undefined} onChange={(e) => patch({ annual_visitors: e.target.value })} />
                <FieldError message={errors.annual_visitors} />
              </div>
              <div className="form-group">
                <label className="form-label" htmlFor="mu-rank">World rank</label>
                <input id="mu-rank" className="form-input" inputMode="numeric" placeholder="e.g. 19" value={form.rank}
                  aria-invalid={!!errors.rank || undefined} onChange={(e) => patch({ rank: e.target.value })} />
                <FieldError message={errors.rank} />
                <div className="xp-section-hint" style={{ margin: '6px 0 0' }}>The app lists museums by this number, 1 first.</div>
              </div>
            </div>
          </section>

          <section className="cte-card">
            <div className="xp-section-title">Guide page</div>
            <div className="form-group">
              <label className="form-label" htmlFor="mu-hours">Opening hours</label>
              <input id="mu-hours" className="form-input" maxLength={200} placeholder="e.g. 9am–6pm (Closed Tue)" value={form.opening_hours}
                onChange={(e) => patch({ opening_hours: e.target.value })} />
              <div className="xp-section-hint" style={{ margin: '6px 0 0' }}>One short line: it shows in a small chip.</div>
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label className="form-label" htmlFor="mu-website">Official website</label>
              <input id="mu-website" className="form-input" maxLength={512} placeholder="https://" value={form.website}
                aria-invalid={!!errors.website || undefined} onChange={(e) => patch({ website: e.target.value })} />
              <FieldError message={errors.website} />
            </div>
          </section>

          <section className="cte-card">
            <div className="xp-section-head" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, flexWrap: 'wrap' }}>
              <div className="xp-section-title" style={{ margin: 0 }}>Must-see items</div>
              <button type="button" className="btn btn-primary btn-sm" onClick={openNew}>
                <PlusIcon size={14} /> Add item
              </button>
            </div>
            <div className="seg" style={{ margin: '14px 0 10px', flexWrap: 'wrap' }}>
              <button type="button" className={`seg-btn ${tab === 'all' ? 'active' : ''}`} onClick={() => setTab('all')}>
                All items <span className="seg-count">{form.items.length}</span>
              </button>
              {DURATIONS.map((d) => (
                <button key={d} type="button" className={`seg-btn ${tab === d ? 'active' : ''}`} onClick={() => setTab(d)}>
                  {TOUR_LABELS[d]} <span className="seg-count">{inTour(d)}</span>
                </button>
              ))}
            </div>
            <div className="xp-section-hint">
              {tab === 'all'
                ? 'Every item in the museum. Tick the tours each one is part of when you add or edit it.'
                : `The ${TOUR_LABELS[tab]} tour in walking order, as the app numbers its stops. Use the arrows to change the order; it does not change other tours.`}
              {tab !== 'all' && inTour(tab) > 1 && (
                <> <button type="button" className="mue-link" onClick={() => followList(tab)}>Use the All items order</button></>
              )}
            </div>

            {listRows.length === 0 ? (
              <div className="mue-empty">
                {tab === 'all' ? 'No items yet. Add the first one with “Add item”.' : `No items in the ${TOUR_LABELS[tab]} tour yet.`}
              </div>
            ) : (
              <div className="mue-list">
                {listRows.map(({ item, number }, i) => (
                  <div key={item.key} className="mue-row">
                    <span className="mue-num">{number}</span>
                    <button type="button" className="mue-main" onClick={() => setEditing({ ...item, isNew: false, checked: false })}>
                      <strong>{item.must_see_item}</strong>
                      <span>{[item.artist, item.room_gallery, item.building].filter(Boolean).join(' · ')}</span>
                      <span className="mue-chips">
                        <Badge tone="blue">{item.category}</Badge>
                        {tab === 'all' && <TourChips item={item} />}
                      </span>
                    </button>
                    <div className="cte-step-tools">
                      <button type="button" className="icon-btn" title="Move up" disabled={i === 0}
                        onClick={() => (tab === 'all' ? moveInList(i, -1) : moveInTour(tab, i, -1))}>
                        <ArrowUpIcon size={15} />
                      </button>
                      <button type="button" className="icon-btn" title="Move down" disabled={i === listRows.length - 1}
                        onClick={() => (tab === 'all' ? moveInList(i, 1) : moveInTour(tab, i, 1))}>
                        <ArrowDownIcon size={15} />
                      </button>
                      <button type="button" className="icon-btn" title="Edit" onClick={() => setEditing({ ...item, isNew: false, checked: false })}>
                        <EditIcon size={15} />
                      </button>
                      {tab === 'all' ? (
                        <button type="button" className="icon-btn danger" title="Remove from the museum" onClick={() => removeItem(item)}>
                          <TrashIcon size={15} />
                        </button>
                      ) : (
                        <button type="button" className="icon-btn danger" title={`Take out of the ${TOUR_LABELS[tab]} tour`} onClick={() => leaveTour(tab, item)}>
                          <TrashIcon size={15} />
                        </button>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </section>

          <section className="cte-card cte-danger">
            <div className="cte-danger-row">
              <div>
                <strong>{detail.is_hidden ? 'Hidden from the app' : 'Shown in the app'}</strong>
                <span>{detail.is_hidden ? 'Switch it on when the photo and items are ready.' : 'Take it out of the app for now without deleting it.'}</span>
              </div>
              <Switch checked={!detail.is_hidden} disabled={!!busy} label={detail.is_hidden ? 'Off' : 'On'} onChange={(on) => setHidden(!on)} />
            </div>
            {isAdmin && (
              <div className="cte-danger-row">
                <div>
                  <strong>Delete this museum</strong>
                  <span>Removes it and all its must-see items for good.</span>
                </div>
                <button type="button" className="btn btn-danger-ghost btn-sm" disabled={!!busy} onClick={remove}>
                  <TrashIcon size={14} /> Delete
                </button>
              </div>
            )}
          </section>

          <div className="xp-savebar cte-savebar">
            {dirty
              ? <span className="unsaved"><span className="dot dot-new" /> Unsaved changes</span>
              : <span>All changes saved</span>}
            <div className="cte-savebar-actions">
              {dirty && (
                <button type="button" className="btn btn-ghost btn-sm" disabled={!!busy} onClick={() => { setForm(base); setChecked(false); }}>Discard</button>
              )}
              <button type="button" className="btn btn-primary btn-sm" disabled={!dirty || !!busy} onClick={save}>
                {busy === 'save' ? 'Saving…' : 'Save'}
              </button>
            </div>
          </div>
        </div>

        <aside className="cte-side">
          <MuseumPreview museum={form} items={form.items} photoUrl={detail.image_url} tour={tab === 'all' ? null : tab} />
        </aside>
      </div>

      {editing && (
        <Drawer
          title={editing.isNew ? 'Add a must-see item' : 'Edit must-see item'}
          subtitle={form.name}
          onClose={() => setEditing(null)}
          onSubmit={saveItem}
          footer={(
            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, width: '100%' }}>
              <button type="button" className="btn btn-ghost btn-sm" onClick={() => setEditing(null)}>Cancel</button>
              <button type="submit" className="btn btn-primary btn-sm">{editing.isNew ? 'Add item' : 'Done'}</button>
            </div>
          )}
        >
          <div className="form-group">
            <label className="form-label" htmlFor="mi-name">Must-see item *</label>
            <input id="mi-name" className="form-input" maxLength={255} placeholder="e.g. The Night Watch" value={editing.must_see_item}
              aria-invalid={!!itemErr.must_see_item || undefined} onChange={(e) => setEditing({ ...editing, must_see_item: e.target.value })} />
            <FieldError message={itemErr.must_see_item} />
          </div>
          <div className="form-group">
            <label className="form-label" htmlFor="mi-artist">Artist / creator</label>
            <input id="mi-artist" className="form-input" maxLength={255} placeholder="e.g. Rembrandt van Rijn" value={editing.artist}
              onChange={(e) => setEditing({ ...editing, artist: e.target.value })} />
          </div>
          <div className="form-group">
            <label className="form-label" htmlFor="mi-category">Category *</label>
            <input id="mi-category" className="form-input" maxLength={120} list="mi-categories" placeholder="e.g. Dutch Golden Age" value={editing.category}
              aria-invalid={!!itemErr.category || undefined} onChange={(e) => setEditing({ ...editing, category: e.target.value })} />
            <datalist id="mi-categories">{categories.map((c) => <option key={c} value={c} />)}</datalist>
            <FieldError message={itemErr.category} />
          </div>
          <div className="form-grid-2">
            <div className="form-group">
              <label className="form-label" htmlFor="mi-building">Building / wing *</label>
              <input id="mi-building" className="form-input" maxLength={255} list="mi-buildings" placeholder="e.g. Main Building" value={editing.building}
                aria-invalid={!!itemErr.building || undefined} onChange={(e) => setEditing({ ...editing, building: e.target.value })} />
              <datalist id="mi-buildings">{buildings.map((b) => <option key={b} value={b} />)}</datalist>
              <FieldError message={itemErr.building} />
            </div>
            <div className="form-group">
              <label className="form-label" htmlFor="mi-room">Room / gallery *</label>
              <input id="mi-room" className="form-input" maxLength={255} placeholder="e.g. Gallery of Honour, 2.12" value={editing.room_gallery}
                aria-invalid={!!itemErr.room_gallery || undefined} onChange={(e) => setEditing({ ...editing, room_gallery: e.target.value })} />
              <FieldError message={itemErr.room_gallery} />
            </div>
          </div>
          <div className="form-group">
            <label className="form-label" htmlFor="mi-desc">Why it’s a must-see</label>
            <textarea id="mi-desc" className="form-textarea" rows={4} maxLength={4000} value={editing.description}
              placeholder="One or two sentences travellers read under the item."
              onChange={(e) => setEditing({ ...editing, description: e.target.value })} />
          </div>
          <div className="form-group">
            <label className="form-label">Part of these tours</label>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              {DURATIONS.map((d) => (
                <Switch key={d} checked={editing[`included_${d}`]} label={TOUR_LABELS[d]}
                  onChange={(on) => setEditing({ ...editing, [`included_${d}`]: on })} />
              ))}
            </div>
            <div className="xp-section-hint" style={{ margin: '8px 0 0' }}>A tour it joins gets it as the last stop; reorder it in that tour’s tab.</div>
          </div>
          <div className="xp-section-hint" style={{ margin: 0 }}>Changes are kept on this page until you press Save.</div>
        </Drawer>
      )}
      <Toast toast={toast} />
    </div>
  );
}
