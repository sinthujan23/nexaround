import { useEffect, useRef, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { apiDelete, apiGet, apiPost, apiPut, apiUpload, mediaUrl } from '../api';
import { Badge, Modal, PageError, PageLoading, Toast } from '../components/Kit';
import {
  ArrowDownIcon, ArrowUpIcon, ChevronDownIcon, ImageIcon, MapPinIcon, TrashIcon,
} from '../components/Icons';
import RichTextEditor from '../components/RichTextEditor';
import LocationPicker from '../components/LocationPicker';
import CityTourLinks from '../components/CityTourLinks';
import CityTourPreview from '../components/CityTourPreview';
import { COUNTRIES } from '../constants/countries';
import {
  MODES, dayPlan, emptyGuide, formatClock, modeOf, newBreak, newDay, newMove, newStop,
  notifyCityToursChanged, stopNumbers, tourBadges, withDays,
} from '../cityTours';
import { isCreator } from '../session';
import { useToast } from '../hooks';

const formatDate = (value) => (value
  ? new Date(value).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })
  : '');

const MaterialIcon = ({ name, size = 18 }) => (
  <span className="material-icons-round" style={{ fontSize: size }} aria-hidden="true">{name}</span>
);

/** One photo: upload, see it, replace or remove it. */
function PhotoField({ value, onChange, onBusy, label, hint }) {
  const input = useRef(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const pick = async (e) => {
    const files = e.target.files;
    if (!files?.length) return;
    setBusy(true);
    onBusy(1);
    setError('');
    try {
      const res = await apiUpload('/admin/city-tours/upload', [files[0]]);
      if (res.urls?.[0]) onChange(res.urls[0]);
    } catch (err) {
      setError(err.message || 'Upload failed.');
    } finally {
      setBusy(false);
      onBusy(-1);
      if (input.current) input.current.value = '';
    }
  };

  return (
    <div className="form-group">
      <label className="form-label">{label}</label>
      <div className="cte-photo">
        <div className="cte-photo-box">
          {value ? <img src={mediaUrl(value)} alt="" /> : <ImageIcon size={22} />}
        </div>
        <div className="cte-photo-actions">
          <button type="button" className="btn btn-ghost btn-sm" disabled={busy} onClick={() => input.current?.click()}>
            {busy ? 'Uploading…' : value ? 'Replace photo' : 'Upload photo'}
          </button>
          {value && !busy && (
            <button type="button" className="btn btn-danger-ghost btn-sm" onClick={() => onChange('')}>Remove</button>
          )}
          {hint && <div className="xp-section-hint" style={{ margin: 0 }}>{hint}</div>}
          {error && <div className="cte-error">{error}</div>}
        </div>
        <input ref={input} type="file" accept="image/jpeg,image/png,image/webp" hidden onChange={pick} />
      </div>
    </div>
  );
}

/** The doc's "Closure / Access" column: when it is shut, what to book. */
function AccessNote({ step, patch }) {
  return (
    <div className="form-group">
      <label className="form-label">Opening & access</label>
      <input
        className="form-input" maxLength={300} value={step.access_note || ''}
        placeholder="e.g. Closed Tuesdays. Book a time slot online."
        onChange={(e) => patch({ access_note: e.target.value })}
      />
    </div>
  );
}

function StopFields({ step, patch, partners, taps, center, onBusy, where }) {
  return (
    <>
      <div className="form-group">
        <label className="form-label">Name of the place *</label>
        <input
          className="form-input" maxLength={120} value={step.name} placeholder="e.g. Eiffel Tower"
          onChange={(e) => patch({ name: e.target.value })}
        />
      </div>
      <LocationPicker
        key={step.id}
        mapId={`cte-map-${step.id}`}
        latitude={step.lat ?? ''}
        longitude={step.lng ?? ''}
        showAddress={false}
        center={center}
        height={220}
        searchEndpoint="/admin/city-tours/place-search"
        searchLabel="Find it on Google, then check the pin"
        searchPlaceholder="e.g. Eiffel Tower, Paris"
        onPick={(p) => {
          const next = {};
          if (p.latitude !== undefined) next.lat = p.latitude === '' ? null : p.latitude;
          if (p.longitude !== undefined) next.lng = p.longitude === '' ? null : p.longitude;
          if (p.name && !step.name.trim()) next.name = p.name;
          patch(next);
        }}
      />
      <PhotoField
        label="Photo" value={step.photo_url} onBusy={onBusy}
        hint="Shown under the name, cropped to 16:10."
        onChange={(url) => patch({ photo_url: url })}
      />
      <div className="form-grid-2">
        <div className="form-group">
          <label className="form-label">Time to spend here</label>
          <input
            className="form-input" maxLength={40} value={step.time_here} placeholder="e.g. 2 hr 45 min"
            onChange={(e) => patch({ time_here: e.target.value })}
          />
        </div>
        <div className="form-group">
          <label className="form-label">Entry price</label>
          <input
            className="form-input" maxLength={80} value={step.price} placeholder="e.g. €29, free under 18"
            onChange={(e) => patch({ price: e.target.value })}
          />
        </div>
      </div>
      <AccessNote step={step} patch={patch} />
      <div className="form-group">
        <label className="form-label">What to see and do</label>
        <RichTextEditor
          value={step.body_md} minHeight={120}
          placeholder="What to see here, tips, where to queue…"
          onChange={(v) => patch({ body_md: v })}
        />
      </div>
      <div className="form-group" style={{ marginBottom: 0 }}>
        <label className="form-label">Partner links</label>
        <CityTourLinks links={step.links} partners={partners} taps={taps} where={where} onChange={(links) => patch({ links })} />
      </div>
    </>
  );
}

function MoveFields({ step, patch, partners, taps, where }) {
  return (
    <>
      <div className="form-group">
        <label className="form-label">How to get there</label>
        <div className="cte-modes">
          {MODES.map((m) => (
            <button
              key={m.key} type="button" className={`cte-mode ${step.mode === m.key ? 'active' : ''}`}
              onClick={() => patch({ mode: m.key })}
            >
              <MaterialIcon name={m.icon} /> {m.label}
            </button>
          ))}
        </div>
      </div>
      <div className="form-group">
        <label className="form-label">Directions</label>
        <input
          className="form-input" maxLength={160} value={step.title}
          placeholder="e.g. Line 6 towards Nation, get off at Bir-Hakeim (4 stops)"
          onChange={(e) => patch({ title: e.target.value })}
        />
      </div>
      <div className="form-grid-2">
        <div className="form-group">
          <label className="form-label">Travel time</label>
          <input
            className="form-input" maxLength={40} value={step.duration} placeholder="e.g. 15 min"
            onChange={(e) => patch({ duration: e.target.value })}
          />
        </div>
        <div className="form-group">
          <label className="form-label">Fare</label>
          <input
            className="form-input" maxLength={60} value={step.cost} placeholder="e.g. €2.15"
            onChange={(e) => patch({ cost: e.target.value })}
          />
        </div>
      </div>
      <AccessNote step={step} patch={patch} />
      <div className="form-group">
        <label className="form-label">More details</label>
        <RichTextEditor
          value={step.body_md} minHeight={90}
          placeholder="Where to buy the ticket, which exit to take…"
          onChange={(v) => patch({ body_md: v })}
        />
      </div>
      <div className="form-group" style={{ marginBottom: 0 }}>
        <label className="form-label">Partner links</label>
        <CityTourLinks links={step.links} partners={partners} taps={taps} where={where} onChange={(links) => patch({ links })} />
      </div>
    </>
  );
}

/** A meal or a rest: no place on the map, just time in the day. */
function BreakFields({ step, patch, partners, taps, where }) {
  return (
    <>
      <div className="form-grid-2">
        <div className="form-group">
          <label className="form-label">Name</label>
          <input
            className="form-input" maxLength={80} value={step.title} placeholder="e.g. Lunch / Rest"
            onChange={(e) => patch({ title: e.target.value })}
          />
        </div>
        <div className="form-group">
          <label className="form-label">How long</label>
          <input
            className="form-input" maxLength={40} value={step.duration} placeholder="e.g. 45 min"
            onChange={(e) => patch({ duration: e.target.value })}
          />
        </div>
      </div>
      <AccessNote step={step} patch={patch} />
      <div className="form-group">
        <label className="form-label">More details</label>
        <RichTextEditor
          value={step.body_md} minHeight={90}
          placeholder="Where to eat nearby, what to try…"
          onChange={(v) => patch({ body_md: v })}
        />
      </div>
      <div className="form-group" style={{ marginBottom: 0 }}>
        <label className="form-label">Partner links</label>
        <CityTourLinks links={step.links} partners={partners} taps={taps} where={where} onChange={(links) => patch({ links })} />
      </div>
    </>
  );
}

/**
 * Write or review one City Tours guide. The phone on the right redraws the
 * guide as the app will show it while you type. Creators save drafts and send
 * them for review; admins approve a version (it goes live as it is) or send it
 * back with a note.
 */
export default function CityTourEditor() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const id = params.get('id');
  const admin = !isCreator();

  const [detail, setDetail] = useState(null);
  const [form, setForm] = useState(() => (id ? null : emptyGuide()));
  const [base, setBase] = useState(form);
  const [partners, setPartners] = useState(null);
  const [loadError, setLoadError] = useState('');
  const [openStep, setOpenStep] = useState(() => form?.days?.[0]?.steps?.[0]?.id || null);
  // The day being worked on: the phone preview shows it.
  const [focusDay, setFocusDay] = useState(null);
  const [uploads, setUploads] = useState(0);
  const [busy, setBusy] = useState('');
  const [sendingBack, setSendingBack] = useState(false);
  const [note, setNote] = useState('');
  const [toast, notify] = useToast(4000);

  const dirty = form !== null && JSON.stringify(form) !== JSON.stringify(base);

  useEffect(() => {
    apiGet('/admin/city-tours/partners').then(setPartners).catch(() => setPartners({ affiliates: [], experiences: [] }));
  }, []);

  useEffect(() => {
    if (!id || detail?.id === id) return;
    let active = true;
    apiGet(`/admin/city-tours/${id}`)
      .then((d) => {
        if (!active) return;
        const content = withDays(d.content);
        setDetail(d);
        setForm(content);
        setBase(content);
        setOpenStep(null);
      })
      .catch((err) => { if (active) setLoadError(err.message || 'Could not load this guide.'); });
    return () => { active = false; };
  }, [id, detail?.id]);

  useEffect(() => {
    if (!dirty) return undefined;
    const warn = (e) => { e.preventDefault(); e.returnValue = ''; };
    window.addEventListener('beforeunload', warn);
    return () => window.removeEventListener('beforeunload', warn);
  }, [dirty]);

  if (loadError) return <PageError error={loadError} onRetry={() => window.location.reload()} />;
  if (!form) return <PageLoading />;

  const patchForm = (patch) => setForm((f) => ({ ...f, ...patch }));
  const patchDay = (dayId, patch) =>
    setForm((f) => ({ ...f, days: f.days.map((d) => (d.id === dayId ? { ...d, ...patch } : d)) }));
  const patchSteps = (dayId, change) =>
    setForm((f) => ({ ...f, days: f.days.map((d) => (d.id === dayId ? { ...d, steps: change(d.steps) } : d)) }));
  const patchStep = (stepId, patch) => setForm((f) => ({
    ...f,
    days: f.days.map((d) => ({ ...d, steps: d.steps.map((s) => (s.id === stepId ? { ...s, ...patch } : s)) })),
  }));

  const addStep = (dayId, kind) => {
    const step = kind === 'stop' ? newStop() : kind === 'break' ? newBreak() : newMove();
    patchSteps(dayId, (steps) => [...steps, step]);
    setOpenStep(step.id);
    setFocusDay(dayId);
  };
  const moveStep = (dayId, index, delta) => patchSteps(dayId, (list) => {
    const steps = [...list];
    const target = index + delta;
    if (target < 0 || target >= steps.length) return list;
    [steps[index], steps[target]] = [steps[target], steps[index]];
    return steps;
  });
  const removeStep = (dayId, step) => {
    const empty = step.type === 'stop'
      ? !step.name && step.lat == null && !step.body_md && !step.links.length
      : !step.title && !step.body_md && !step.links.length;
    if (!empty && !confirm('Remove this step and everything written in it?')) return;
    patchSteps(dayId, (steps) => steps.filter((s) => s.id !== step.id));
  };

  const addDay = () => {
    const day = newDay(true);
    setForm((f) => ({ ...f, days: [...f.days, day] }));
    setOpenStep(day.steps[0].id);
    setFocusDay(day.id);
  };
  const moveDay = (index, delta) => setForm((f) => {
    const days = [...f.days];
    const target = index + delta;
    if (target < 0 || target >= days.length) return f;
    [days[index], days[target]] = [days[target], days[index]];
    return { ...f, days };
  });
  const removeDay = (day) => {
    if (day.steps.length && !confirm(`Remove this day and its ${day.steps.length} steps?`)) return;
    setForm((f) => ({ ...f, days: f.days.filter((d) => d.id !== day.id) }));
  };

  const applySaved = (saved, sent) => {
    const content = withDays(saved.content);
    setDetail(saved);
    setBase(content);
    // Kept if more was typed while the save was on its way.
    setForm((current) => (current === sent ? content : current));
  };

  const run = async (label, work) => {
    setBusy(label);
    try {
      await work();
    } catch (err) {
      notify(err.message || 'Something went wrong.', 'error');
    } finally {
      setBusy('');
    }
  };

  // Saves when there is something to save; returns the guide as it now is.
  const saveNow = async () => {
    if (!dirty && detail) return detail;
    const sent = form;
    const saved = detail
      ? await apiPut(`/admin/city-tours/${detail.id}`, { content: sent, version: detail.version })
      : await apiPost('/admin/city-tours', { content: sent });
    applySaved(saved, sent);
    if (!detail) navigate(`/city-tours/edit?id=${saved.id}`, { replace: true });
    return saved;
  };

  const save = () => run('save', async () => {
    await saveNow();
    notify('Saved');
  });

  const submit = () => run('submit', async () => {
    const saved = await saveNow();
    const sent = await apiPost(`/admin/city-tours/${saved.id}/submit`, { version: saved.version });
    applySaved(sent, sent.content);
    notifyCityToursChanged();
    notify('Sent for review. An admin will check it and put it live.');
  });

  const approve = () => {
    if (!confirm('Put this version live in the app? Travellers will see it as the preview shows.')) return;
    run('approve', async () => {
      const saved = await saveNow();
      const done = await apiPost(`/admin/city-tours/${saved.id}/review`, { decision: 'approve', version: saved.version });
      applySaved(done, done.content);
      notifyCityToursChanged();
      notify('Live in the app');
    });
  };

  const sendBack = () => run('sendback', async () => {
    const done = await apiPost(`/admin/city-tours/${detail.id}/review`, {
      decision: 'request_changes', note, version: detail.version,
    });
    applySaved(done, done.content);
    setSendingBack(false);
    setNote('');
    notifyCityToursChanged();
    notify('Sent back to the creator');
  });

  const setHidden = (hidden) => run('hide', async () => {
    // Only the guide's state changes; anything typed but not saved stays.
    setDetail(await apiPost(`/admin/city-tours/${detail.id}/visibility`, { hidden }));
    notify(hidden ? 'Hidden from the app' : 'Back in the app');
  });

  const remove = () => {
    if (!confirm(detail.is_live
      ? 'Delete this guide? It leaves the app now, with its tap counts.'
      : 'Delete this guide for good?')) return;
    run('delete', async () => {
      await apiDelete(`/admin/city-tours/${detail.id}`);
      notifyCityToursChanged();
      navigate('/city-tours', { replace: true });
    });
  };

  const back = () => {
    if (dirty && !confirm('Leave without saving your changes?')) return;
    if (window.history.length > 1) navigate(-1);
    else navigate('/city-tours');
  };

  const status = detail?.review_status || 'draft';
  const taps = admin ? detail?.link_taps || {} : undefined;
  const severalDays = form.days.length > 1;
  // The pin a new stop's map opens at: the stop before it, on this day or an earlier one.
  const lastPin = (dayIndex, index) => {
    const before = [
      ...form.days.slice(0, dayIndex).flatMap((d) => d.steps),
      ...form.days[dayIndex].steps.slice(0, index),
    ];
    const stop = [...before].reverse().find((s) => s.type === 'stop' && s.lat != null && s.lng != null);
    return stop ? [Number(stop.lat), Number(stop.lng)] : null;
  };
  // Where a step's partner links sit: what their pages are made from.
  const linkPlace = (day, index) => {
    const step = day.steps[index];
    const stopName = (s) => (s && s.type === 'stop' ? s.name : '');
    return {
      city: form.city.trim(),
      country: form.country.trim(),
      isStop: step.type === 'stop',
      stopName: stopName(step).trim(),
      place: stopName(step).trim(),
      prevStop: stopName([...day.steps.slice(0, index)].reverse().find((s) => s.type === 'stop')).trim(),
      nextStop: stopName(day.steps.slice(index + 1).find((s) => s.type === 'stop')).trim(),
    };
  };
  const canSend = !admin && (dirty || status === 'draft' || status === 'changes_requested');
  const canApprove = admin && (dirty || status !== 'approved');

  return (
    <div className="cte">
      <div className="cte-head">
        <button type="button" className="xp-back" onClick={back}>← All guides</button>
        <div className="cte-title-row">
          <div className="cte-title">{form.title || (detail ? 'Untitled guide' : 'New guide')}</div>
          {detail && tourBadges(detail).map((b) => <Badge key={b.label} tone={b.tone}>{b.label}</Badge>)}
        </div>
        {detail && (
          <div className="xp-detail-sub">
            By {detail.author_name} · saved {formatDate(detail.updated_at)}
            {detail.published_at && ` · first live ${formatDate(detail.published_at)}`}
            {admin && detail.is_live && ` · ${detail.taps || 0} partner taps`}
          </div>
        )}
      </div>

      {status === 'changes_requested' && detail?.review_note && (
        <div className="cte-banner warn">
          <strong>Sent back{detail.reviewed_by ? ` by ${detail.reviewed_by}` : ''}:</strong> {detail.review_note}
          <div>Make the changes, then send it for review again.</div>
        </div>
      )}
      {status === 'pending' && (
        <div className="cte-banner">
          {admin
            ? 'Waiting for your review. Check it in the preview, then put it live or send it back with a note.'
            : 'Waiting for review. If you change it now, send it again afterwards.'}
        </div>
      )}
      {detail?.is_live && status !== 'approved' && (
        <div className="cte-banner">
          The app still shows the version approved on {formatDate(detail.reviewed_at || detail.published_at)}.
          These changes reach travellers once an admin approves them.
        </div>
      )}

      <div className="cte-grid">
        <div className="cte-form">
          <section className="cte-card">
            <div className="xp-section-title">About the guide</div>
            <div className="xp-section-hint">The cover, title and short intro also show on the guide’s card in the city list.</div>
            <PhotoField
              label="Cover photo *" value={form.cover_url} onBusy={(d) => setUploads((n) => n + d)}
              hint="A wide photo of the city or the first stop."
              onChange={(url) => patchForm({ cover_url: url })}
            />
            <div className="form-grid-2">
              <div className="form-group">
                <label className="form-label">City *</label>
                <input
                  className="form-input" maxLength={80} value={form.city} placeholder="e.g. Paris"
                  onChange={(e) => patchForm({ city: e.target.value })}
                />
              </div>
              <div className="form-group">
                <label className="form-label">Country *</label>
                <input
                  className="form-input" maxLength={80} value={form.country} list="cte-countries" placeholder="e.g. France"
                  onChange={(e) => patchForm({ country: e.target.value })}
                />
                <datalist id="cte-countries">
                  {COUNTRIES.map((c) => <option key={c.code} value={c.name} />)}
                </datalist>
              </div>
            </div>
            <div className="form-group">
              <label className="form-label">Title *</label>
              <input
                className="form-input" maxLength={120} value={form.title} placeholder="e.g. Paris in a day: the icons by metro"
                onChange={(e) => patchForm({ title: e.target.value })}
              />
            </div>
            <div className="form-group">
              <label className="form-label">Short intro * <span className="muted">({form.summary.length}/300)</span></label>
              <textarea
                className="form-textarea" rows={3} maxLength={300} value={form.summary}
                placeholder="One or two sentences on what this route covers"
                onChange={(e) => patchForm({ summary: e.target.value })}
              />
            </div>
            <div className="form-grid-2">
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label className="form-label">How long it takes</label>
                <input
                  className="form-input" maxLength={40} value={form.duration} placeholder="e.g. 6–7 hours"
                  onChange={(e) => patchForm({ duration: e.target.value })}
                />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label className="form-label">Budget</label>
                <input
                  className="form-input" maxLength={60} value={form.budget} placeholder="e.g. €40–60 per person"
                  onChange={(e) => patchForm({ budget: e.target.value })}
                />
              </div>
            </div>
          </section>

          <section className="cte-card">
            <div className="xp-section-title">Before you start</div>
            <div className="xp-section-hint">Optional. Shown above the route: passes to buy, the best time to go, what to bring.</div>
            <RichTextEditor
              value={form.intro_md} minHeight={120}
              placeholder="Write it like a document: use Heading for each part"
              onChange={(v) => patchForm({ intro_md: v })}
            />
          </section>

          <section className="cte-card">
            <div className="xp-section-title">Days</div>
            <div className="xp-section-hint">
              One day for each group of places, the must-sees first: a traveller with 3 days gets Days 1 to 3, or picks
              the days whose places they want. In each day, add the places, the rides between them and breaks in order.
              The times come from the day’s start and how long each step takes.
            </div>
            {form.days.map((day, d) => {
              const plan = dayPlan(day);
              const numbers = stopNumbers(day.steps);
              const places = day.steps.filter((s) => s.type === 'stop').length;
              return (
                <div key={day.id} className={`cte-day ${focusDay === day.id ? 'focus' : ''}`} onFocusCapture={() => setFocusDay(day.id)}>
                  <div className="cte-day-head">
                    <strong>Day {d + 1}</strong>
                    <span>
                      {[plan.start !== null ? `${formatClock(plan.start)} – ${formatClock(plan.end)}` : '',
                        `${places} place${places === 1 ? '' : 's'}`].filter(Boolean).join(' · ')}
                    </span>
                    {severalDays && (
                      <div className="cte-step-tools">
                        <button type="button" className="icon-btn" title="Move day up" disabled={d === 0} onClick={() => moveDay(d, -1)}>
                          <ArrowUpIcon size={15} />
                        </button>
                        <button type="button" className="icon-btn" title="Move day down" disabled={d === form.days.length - 1} onClick={() => moveDay(d, 1)}>
                          <ArrowDownIcon size={15} />
                        </button>
                        <button type="button" className="icon-btn danger" title="Remove day" onClick={() => removeDay(day)}>
                          <TrashIcon size={15} />
                        </button>
                      </div>
                    )}
                  </div>
                  <div className="cte-day-fields">
                    <div className="form-group">
                      <label className="form-label">Places this day{severalDays ? ' *' : ''}</label>
                      <input
                        className="form-input" maxLength={160} value={day.title}
                        placeholder="e.g. Eiffel Tower, Champ de Mars, Seine Cruise and Invalides"
                        onChange={(e) => patchDay(day.id, { title: e.target.value })}
                      />
                    </div>
                    <div className="form-group">
                      <label className="form-label">Starts at</label>
                      <input
                        className="form-input" type="time" value={day.starts_at || ''}
                        onChange={(e) => patchDay(day.id, { starts_at: e.target.value })}
                      />
                    </div>
                  </div>
                  <div className="cte-steps">
                    {day.steps.map((step, i) => {
                      const open = openStep === step.id;
                      const mode = modeOf(step.mode);
                      const pinned = step.lat != null && step.lng != null;
                      const linkCount = step.links.length
                        ? `${step.links.length} partner link${step.links.length > 1 ? 's' : ''}` : '';
                      const time = plan.times[step.id];
                      const when = time ? `${formatClock(time[0])} – ${formatClock(time[1])}` : '';
                      return (
                        <div key={step.id} className={`cte-step ${open ? 'open' : ''}`}>
                          <div
                            className="cte-step-head"
                            onClick={() => { setOpenStep(open ? null : step.id); setFocusDay(day.id); }}
                          >
                            {step.type === 'stop'
                              ? <span className={`ctp-badge ${numbers[step.id] === 1 ? 'start' : ''}`}>{numbers[step.id]}</span>
                              : <span className="ctp-mode"><MaterialIcon name={step.type === 'break' ? 'restaurant' : mode.icon} size={15} /></span>}
                            <div className="cte-step-title">
                              <strong>
                                {step.type === 'stop'
                                  ? step.name || 'New stop'
                                  : step.type === 'break'
                                    ? step.title || 'Break'
                                    : [mode.label, step.title].filter(Boolean).join(' · ')}
                              </strong>
                              <span>
                                {step.type === 'stop'
                                  ? [when, pinned ? 'on the map' : 'not on the map yet', linkCount].filter(Boolean).join(' · ')
                                  : [when || (step.type === 'break' ? 'Break' : 'Travel'), step.duration, step.cost, linkCount]
                                    .filter(Boolean).join(' · ')}
                              </span>
                            </div>
                            <div className="cte-step-tools" onClick={(e) => e.stopPropagation()}>
                              <button type="button" className="icon-btn" title="Move up" disabled={i === 0} onClick={() => moveStep(day.id, i, -1)}>
                                <ArrowUpIcon size={15} />
                              </button>
                              <button type="button" className="icon-btn" title="Move down" disabled={i === day.steps.length - 1} onClick={() => moveStep(day.id, i, 1)}>
                                <ArrowDownIcon size={15} />
                              </button>
                              <button type="button" className="icon-btn danger" title="Remove" onClick={() => removeStep(day.id, step)}>
                                <TrashIcon size={15} />
                              </button>
                            </div>
                            <ChevronDownIcon size={18} className={`cte-chevron ${open ? 'up' : ''}`} />
                          </div>
                          {open && (
                            <div className="cte-step-body">
                              {step.type === 'stop' && (
                                <StopFields
                                  step={step} partners={partners} taps={taps} center={lastPin(d, i)} where={linkPlace(day, i)}
                                  onBusy={(n) => setUploads((u) => u + n)}
                                  patch={(p) => patchStep(step.id, p)}
                                />
                              )}
                              {step.type === 'move' && (
                                <MoveFields
                                  step={step} partners={partners} taps={taps} where={linkPlace(day, i)}
                                  patch={(p) => patchStep(step.id, p)}
                                />
                              )}
                              {step.type === 'break' && (
                                <BreakFields
                                  step={step} partners={partners} taps={taps} where={linkPlace(day, i)}
                                  patch={(p) => patchStep(step.id, p)}
                                />
                              )}
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </div>
                  <div className="cte-add">
                    <button type="button" className="btn btn-ghost btn-sm" onClick={() => addStep(day.id, 'move')}>
                      <MaterialIcon name="directions_walk" size={16} /> Add travel to the next stop
                    </button>
                    <button type="button" className="btn btn-ghost btn-sm" onClick={() => addStep(day.id, 'stop')}>
                      <MapPinIcon size={14} /> Add a stop
                    </button>
                    <button type="button" className="btn btn-ghost btn-sm" onClick={() => addStep(day.id, 'break')}>
                      <MaterialIcon name="restaurant" size={16} /> Add a break
                    </button>
                  </div>
                </div>
              );
            })}
            {form.days.length < 14 && (
              <button type="button" className="btn btn-ghost btn-sm" onClick={addDay}>
                <MaterialIcon name="calendar_today" size={15} /> Add a day
              </button>
            )}
          </section>

          <section className="cte-card">
            <div className="xp-section-title">{admin ? 'Before it goes live' : 'Before you send it'}</div>
            {!detail || dirty ? (
              <div className="xp-section-hint" style={{ margin: 0 }}>Save to check what is still missing.</div>
            ) : detail.problems.length ? (
              <ul className="cte-problems">{detail.problems.map((p) => <li key={p}>{p}</li>)}</ul>
            ) : (
              <div className="cte-ok">Everything needed is there.</div>
            )}
          </section>

          {detail && (admin || !detail.is_live) && (
            <section className="cte-card cte-danger">
              {admin && detail.is_live && (
                <div className="cte-danger-row">
                  <div>
                    <strong>{detail.is_hidden ? 'Hidden from the app' : 'Shown in the app'}</strong>
                    <span>{detail.is_hidden ? 'Travellers cannot open it. Its text and taps are kept.' : 'Take it off the app for now without deleting it.'}</span>
                  </div>
                  <button type="button" className="btn btn-ghost btn-sm" disabled={!!busy} onClick={() => setHidden(!detail.is_hidden)}>
                    {detail.is_hidden ? 'Show in the app' : 'Hide from the app'}
                  </button>
                </div>
              )}
              <div className="cte-danger-row">
                <div>
                  <strong>Delete this guide</strong>
                  <span>{detail.is_live ? 'It leaves the app at once, with its tap counts.' : 'It has never been live.'}</span>
                </div>
                <button type="button" className="btn btn-danger-ghost btn-sm" disabled={!!busy} onClick={remove}>
                  <TrashIcon size={14} /> Delete
                </button>
              </div>
            </section>
          )}

          <div className="xp-savebar cte-savebar">
            {dirty
              ? <span className="unsaved"><span className="dot dot-new" /> Unsaved changes</span>
              : <span>{detail ? 'All changes saved' : 'Not saved yet'}</span>}
            <div className="cte-savebar-actions">
              {dirty && detail && (
                <button type="button" className="btn btn-ghost btn-sm" disabled={!!busy} onClick={() => setForm(base)}>Discard</button>
              )}
              <button type="button" className="btn btn-ghost btn-sm" disabled={!dirty || !!busy || uploads > 0} onClick={save}>
                {uploads > 0 ? 'Uploading…' : busy === 'save' ? 'Saving…' : 'Save draft'}
              </button>
              {!admin && (
                <button type="button" className="btn btn-primary btn-sm" disabled={!canSend || !!busy || uploads > 0} onClick={submit}>
                  {busy === 'submit' ? 'Sending…' : status === 'pending' && !dirty ? 'Waiting for review' : status === 'approved' && !dirty ? 'Live' : 'Send for review'}
                </button>
              )}
              {admin && status === 'pending' && !dirty && (
                <button type="button" className="btn btn-ghost btn-sm" disabled={!!busy} onClick={() => setSendingBack(true)}>
                  Send back
                </button>
              )}
              {admin && (
                <button type="button" className="btn btn-primary btn-sm" disabled={!canApprove || !!busy || uploads > 0} onClick={approve}>
                  {busy === 'approve' ? 'Publishing…' : canApprove ? 'Approve & put live' : 'Live'}
                </button>
              )}
            </div>
          </div>
        </div>

        <aside className="cte-side">
          <CityTourPreview content={form} partners={partners} activeDayId={focusDay} />
        </aside>
      </div>

      {sendingBack && (
        <Modal title="Send back to the creator" onClose={() => setSendingBack(false)} maxWidth="520px">
          <div className="form-group">
            <label className="form-label">What needs changing *</label>
            <textarea
              className="form-textarea" rows={5} maxLength={2000} value={note} autoFocus
              placeholder="e.g. Stop 3 needs a photo, and the metro line is wrong: it is line 1."
              onChange={(e) => setNote(e.target.value)}
            />
          </div>
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8 }}>
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => setSendingBack(false)}>Cancel</button>
            <button type="button" className="btn btn-primary btn-sm" disabled={!note.trim() || !!busy} onClick={sendBack}>
              {busy === 'sendback' ? 'Sending…' : 'Send back'}
            </button>
          </div>
        </Modal>
      )}
      <Toast toast={toast} />
    </div>
  );
}
