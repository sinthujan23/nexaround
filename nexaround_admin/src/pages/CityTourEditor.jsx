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
  MODES, emptyGuide, modeOf, newMove, newStop, notifyCityToursChanged, stopNumbers, tourBadges,
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

function StopFields({ step, patch, partners, taps, center, onBusy }) {
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
            className="form-input" maxLength={40} value={step.time_here} placeholder="e.g. 1–2 hours"
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
        <CityTourLinks links={step.links} partners={partners} taps={taps} onChange={(links) => patch({ links })} />
      </div>
    </>
  );
}

function MoveFields({ step, patch, partners, taps }) {
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
        <CityTourLinks links={step.links} partners={partners} taps={taps} onChange={(links) => patch({ links })} />
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
  const [openStep, setOpenStep] = useState(() => form?.steps?.[0]?.id || null);
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
        setDetail(d);
        setForm(d.content);
        setBase(d.content);
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
  const patchStep = (stepId, patch) =>
    setForm((f) => ({ ...f, steps: f.steps.map((s) => (s.id === stepId ? { ...s, ...patch } : s)) }));

  const addStep = (kind) => {
    const step = kind === 'stop' ? newStop() : newMove();
    setForm((f) => ({ ...f, steps: [...f.steps, step] }));
    setOpenStep(step.id);
  };
  const moveStep = (index, delta) => setForm((f) => {
    const steps = [...f.steps];
    const target = index + delta;
    if (target < 0 || target >= steps.length) return f;
    [steps[index], steps[target]] = [steps[target], steps[index]];
    return { ...f, steps };
  });
  const removeStep = (step) => {
    const empty = step.type === 'stop'
      ? !step.name && step.lat == null && !step.body_md && !step.links.length
      : !step.title && !step.body_md && !step.links.length;
    if (!empty && !confirm('Remove this step and everything written in it?')) return;
    setForm((f) => ({ ...f, steps: f.steps.filter((s) => s.id !== step.id) }));
  };

  const applySaved = (saved, sent) => {
    setDetail(saved);
    setBase(saved.content);
    // Kept if more was typed while the save was on its way.
    setForm((current) => (current === sent ? saved.content : current));
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
  const numbers = stopNumbers(form.steps);
  const taps = admin ? detail?.link_taps || {} : undefined;
  const lastPin = (index) => {
    for (let i = index - 1; i >= 0; i -= 1) {
      const s = form.steps[i];
      if (s.type === 'stop' && s.lat != null && s.lng != null) return [Number(s.lat), Number(s.lng)];
    }
    return null;
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
            <div className="xp-section-title">The route</div>
            <div className="xp-section-hint">
              Start with the place where the journey begins. Then add how to get to the next stop, the next stop, and so on.
            </div>
            <div className="cte-steps">
              {form.steps.map((step, i) => {
                const open = openStep === step.id;
                const mode = modeOf(step.mode);
                const pinned = step.lat != null && step.lng != null;
                return (
                  <div key={step.id} className={`cte-step ${open ? 'open' : ''}`}>
                    <div className="cte-step-head" onClick={() => setOpenStep(open ? null : step.id)}>
                      {step.type === 'stop'
                        ? <span className={`ctp-badge ${numbers[step.id] === 1 ? 'start' : ''}`}>{numbers[step.id]}</span>
                        : <span className="ctp-mode"><MaterialIcon name={mode.icon} size={15} /></span>}
                      <div className="cte-step-title">
                        <strong>
                          {step.type === 'stop'
                            ? step.name || 'New stop'
                            : [mode.label, step.title].filter(Boolean).join(' · ')}
                        </strong>
                        <span>
                          {step.type === 'stop'
                            ? [i === 0 ? 'Start' : 'Stop', pinned ? 'on the map' : 'not on the map yet',
                              step.links.length ? `${step.links.length} partner link${step.links.length > 1 ? 's' : ''}` : '']
                              .filter(Boolean).join(' · ')
                            : ['Travel', step.duration, step.cost,
                              step.links.length ? `${step.links.length} partner link${step.links.length > 1 ? 's' : ''}` : '']
                              .filter(Boolean).join(' · ')}
                        </span>
                      </div>
                      <div className="cte-step-tools" onClick={(e) => e.stopPropagation()}>
                        <button type="button" className="icon-btn" title="Move up" disabled={i === 0} onClick={() => moveStep(i, -1)}>
                          <ArrowUpIcon size={15} />
                        </button>
                        <button type="button" className="icon-btn" title="Move down" disabled={i === form.steps.length - 1} onClick={() => moveStep(i, 1)}>
                          <ArrowDownIcon size={15} />
                        </button>
                        <button type="button" className="icon-btn danger" title="Remove" onClick={() => removeStep(step)}>
                          <TrashIcon size={15} />
                        </button>
                      </div>
                      <ChevronDownIcon size={18} className={`cte-chevron ${open ? 'up' : ''}`} />
                    </div>
                    {open && (
                      <div className="cte-step-body">
                        {step.type === 'stop' ? (
                          <StopFields
                            step={step} partners={partners} taps={taps} center={lastPin(i)}
                            onBusy={(d) => setUploads((n) => n + d)}
                            patch={(p) => patchStep(step.id, p)}
                          />
                        ) : (
                          <MoveFields step={step} partners={partners} taps={taps} patch={(p) => patchStep(step.id, p)} />
                        )}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
            <div className="cte-add">
              <button type="button" className="btn btn-ghost btn-sm" onClick={() => addStep('move')}>
                <MaterialIcon name="directions_walk" size={16} /> Add travel to the next stop
              </button>
              <button type="button" className="btn btn-ghost btn-sm" onClick={() => addStep('stop')}>
                <MapPinIcon size={14} /> Add a stop
              </button>
            </div>
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
          <CityTourPreview content={form} partners={partners} />
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
