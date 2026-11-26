import { useEffect, useState } from 'react';
import { apiDelete, apiGet, apiPatch, apiPost } from '../api';
import {
  ArrowDownIcon, ArrowUpIcon, BarChartIcon, CalendarIcon, CheckCircleIcon, CreditCardIcon, EditIcon,
  GridIcon, MessageCircleIcon, PlusIcon, QuoteIcon, ThumbsUpIcon, TrashIcon, UsersIcon, WrenchIcon,
} from '../components/Icons';
import { Drawer } from '../components/Kit';
import { FEATURE_LABELS, formatDate } from '../feedbackShared';

// The quarterly survey: results per round, and the rounds themselves. The
// questions are fixed (so quarters compare); the team edits only each round's
// "What should we build next?" options.

const TZ_OFFSET = '+05:30'; // Asia/Colombo, like every date in the panel

const PRICE_LABELS = { lt2: 'Under $2', '2to5': '$2 – $5', '5to8': '$5 – $8', '8to12': '$8 – $12', gt12: 'Over $12' };
const WHY_LABELS = { free_apps: 'Free apps do this', travel_rarely: 'I travel rarely', too_expensive: 'Too expensive', other: 'Other' };
const PLAN_LABELS = { voyager: 'Voyager', globetrotter: 'Globetrotter' };
const QUICK_LABELS = { odyssey: 'Odyssey', city_guides: 'City Guides', walking_challenge: 'Walking Challenge' };

// What the team may give a "build next" option; the app draws the matching icon.
const ICON_LABELS = {
  lightbulb: 'Light bulb', wifi_off: 'Offline', public: 'Globe', hotel: 'Hotel', flight: 'Plane',
  notifications_active: 'Alert bell', groups: 'People', dark_mode: 'Moon', translate: 'Languages', map: 'Map',
  directions_car: 'Car', restaurant: 'Food', photo_camera: 'Camera', payments: 'Money', train: 'Train',
  hiking: 'Hiking', event: 'Calendar', language: 'Web',
};

const SUGGESTED_OPTIONS = [
  { label: 'Offline maps', icon: 'wifi_off' },
  { label: 'Plan trips across countries', icon: 'public' },
  { label: 'Hotel booking in the app', icon: 'hotel' },
  { label: 'Flight price alerts', icon: 'notifications_active' },
  { label: 'Group chat for trips', icon: 'groups' },
  { label: 'Dark mode', icon: 'dark_mode' },
  { label: 'More languages', icon: 'translate' },
];

const pct = (v) => (v == null ? '—' : `${v}%`);

function Delta({ now, before, unit = '' }) {
  if (now == null || before == null) return null;
  const d = now - before;
  if (d === 0) return <span className="fb-delta flat">same as before</span>;
  return <span className={`fb-delta ${d > 0 ? 'up' : 'down'}`}>{d > 0 ? '+' : ''}{d}{unit} vs before</span>;
}

function Kpi({ Icon, color, label, value, sub, delta }) {
  return (
    <div className="fb-kpi">
      <div className="fb-kpi-top">
        <span className="fb-kpi-icon" style={{ color, background: `${color}1a` }}><Icon size={18} /></span>
        {delta}
      </div>
      <div className="fb-kpi-label">{label}</div>
      <div className="fb-kpi-value">{value}</div>
      {sub && <div className="fb-kpi-sub">{sub}</div>}
    </div>
  );
}

function Gauge({ score }) {
  // -100..100 drawn as a half circle; the needle sits on the score.
  const angle = score == null ? 0 : ((score + 100) / 200) * 180;
  return (
    <div className="fb-gauge" title="Net Promoter Score: % who gave 9–10 minus % who gave 0–6">
      <div className="fb-gauge-arc" />
      <div className="fb-gauge-needle" style={{ transform: `rotate(${angle - 90}deg)` }} />
      <div className="fb-gauge-value">{score == null ? '—' : (score > 0 ? `+${score}` : score)}</div>
    </div>
  );
}

function Bars({ rows, color, marks = {} }) {
  const max = Math.max(1, ...rows.map((r) => r.pct || 0));
  return (
    <div className="fb-bars">
      {rows.map((r) => (
        <div key={r.key}>
          <div className="fb-bar">
            <span className="fb-bar-label" title={r.label}>{r.label}</span>
            <span className="fb-bar-track"><i style={{ width: `${((r.pct || 0) / max) * 100}%`, background: color }} /></span>
            <span className="fb-bar-pct">{pct(r.pct)}</span>
            <span className="fb-bar-delta">{r.delta != null && r.delta !== 0 && (
              <em className={r.delta > 0 ? 'up' : 'down'}>{r.delta > 0 ? '+' : ''}{r.delta}</em>
            )}</span>
          </div>
          {r.note && <div className="fb-bar-note">{r.note}</div>}
          {marks[r.key] && <div className="fb-bar-mark">▲ {marks[r.key]}</div>}
        </div>
      ))}
    </div>
  );
}

function Panel({ Icon, color, title, sub, children }) {
  return (
    <div className="fb-panel">
      <div className="fb-panel-head">
        <span className="fb-kpi-icon" style={{ color, background: `${color}1a` }}><Icon size={17} /></span>
        <div><b>{title}</b>{sub && <div className="fb-muted">{sub}</div>}</div>
      </div>
      {children}
    </div>
  );
}

const stateChip = (state) => ({
  open: ['Open', 'st-open'], scheduled: ['Starts later', 'st-scheduled'], ended: ['Ended', 'st-ended'], closed: ['Closed', 'st-closed'],
}[state] || [state, '']);

export function SurveyResults({ notify, onCreate }) {
  const [rounds, setRounds] = useState(null);
  const [roundId, setRoundId] = useState(null);
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    apiGet('/admin/survey/rounds')
      .then((res) => {
        setRounds(res.rounds);
        const open = res.rounds.find((r) => r.state === 'open');
        setRoundId((open || res.rounds[0])?.id || null);
      })
      .catch((err) => setError(err.message || 'Could not load surveys.'));
  }, []);

  useEffect(() => {
    if (!roundId) return undefined;
    let alive = true;
    apiGet(`/admin/survey/rounds/${roundId}/results`)
      .then((res) => { if (alive) { setData(res); setError(null); } })
      .catch((err) => { if (alive) { setError(err.message || 'Could not load the results.'); notify(err.message || 'Could not load the results.', 'error'); } });
    return () => { alive = false; };
  }, [roundId, notify]);

  if (error && !rounds) return <div className="login-error">{error}</div>;
  if (!rounds) return <div className="loader" />;
  if (!rounds.length) {
    return (
      <div className="fb-empty-card">
        <BarChartIcon size={34} />
        <strong>No survey yet</strong>
        <p>Create the first quarterly survey in Survey settings. Explorers see it on Home while it is open.</p>
        <button type="button" className="btn btn-primary" onClick={onCreate}><PlusIcon size={15} /> Create a survey</button>
      </div>
    );
  }

  const prev = data?.previous;
  const loading = !data || data.round?.id !== roundId;
  const pickRound = (id) => { setData(null); setRoundId(id); };

  return (
    <div className="fb-results">
      <div className="fb-results-bar">
        <label className="fb-round-pick">
          <CalendarIcon size={16} />
          <select className="xp-select" value={roundId || ''} onChange={(e) => pickRound(e.target.value)} aria-label="Survey">
            {rounds.map((r) => <option key={r.id} value={r.id}>{r.name} · {stateChip(r.state)[0]} · {r.answers} answers</option>)}
          </select>
        </label>
        {data && !loading && (
          <span className="fb-muted">
            {formatDate(data.round.starts_at)} – {formatDate(data.round.ends_at)}
            {prev && <> · compared with {prev.name}</>}
          </span>
        )}
      </div>

      {loading ? <div className="loader" /> : data.answers === 0 ? (
        <div className="fb-empty-card">
          <BarChartIcon size={34} />
          <strong>No answers yet</strong>
          <p>{data.round.state === 'open'
            ? `The survey is open until ${formatDate(data.round.ends_at)}. Answers show here as they come in.`
            : 'This survey has no answers.'}</p>
        </div>
      ) : (
        <>
          <div className="fb-kpis">
            <Kpi Icon={UsersIcon} color="#2563eb" label="Answers" value={data.answers.toLocaleString()}
              sub={data.answer_rate != null ? `${data.answer_rate}% of ${data.active_explorers.toLocaleString()} active explorers` : null}
              delta={prev && <Delta now={data.answers} before={prev.answers} />} />
            <div className="fb-kpi">
              <div className="fb-kpi-top">
                <span className="fb-kpi-icon" style={{ color: '#007a7c', background: '#007a7c1a' }}><ThumbsUpIcon size={18} /></span>
                {prev && <Delta now={data.nps.score} before={prev.nps} />}
              </div>
              <div className="fb-kpi-label">Would recommend (NPS)</div>
              <Gauge score={data.nps.score} />
              <div className="fb-kpi-sub">{data.nps.promoters}% gave 9–10 · {data.nps.detractors}% gave 0–6</div>
            </div>
            <Kpi Icon={CreditCardIcon} color="#ca8a04" label="Would pay" value={pct(data.would_pay_pct)}
              sub={`Yes ${pct(data.would_pay.yes)} · Maybe ${pct(data.would_pay.maybe)}`}
              delta={prev && <Delta now={data.would_pay_pct} before={prev.would_pay_pct} unit="%" />} />
            <Kpi Icon={CreditCardIcon} color="#7c3aed" label="Fair price, most picked"
              value={data.top_price ? PRICE_LABELS[data.top_price] : '—'} sub="a month, among Yes + Maybe" />
            <Kpi Icon={CheckCircleIcon} color="#059669" label={'"Good" quick ratings'} value={pct(data.quick_good_pct)}
              sub={Object.entries(data.quick).filter(([, q]) => q.count).map(([k, q]) => `${QUICK_LABELS[k]} ${pct(q.good_pct)}`).join(' · ') || 'none yet'}
              delta={prev && <Delta now={data.quick_good_pct} before={prev.quick_good_pct} unit="%" />} />
          </div>

          <div className="fb-panels">
            <Panel Icon={WrenchIcon} color="#007a7c" title="What should we build next?" sub="share of answers that picked it · change vs before">
              <Bars color="#007a7c" rows={data.build_next.map((b) => ({
                key: b.key, label: b.label, pct: b.pct,
                delta: prev && prev.build_next[b.key] != null && b.pct != null ? b.pct - prev.build_next[b.key] : null,
                note: b.first ? `${b.first} picked it first` : null,
              }))} />
            </Panel>
            <Panel Icon={GridIcon} color="#2563eb" title="Features people say they use" sub="compare with Feature usage (what they really open)">
              <Bars color="#2563eb" rows={data.features.map((f) => ({
                key: f.key, label: FEATURE_LABELS[f.key] || f.key, pct: f.pct,
                delta: prev && prev.features[f.key] != null && f.pct != null ? f.pct - prev.features[f.key] : null,
              }))} />
            </Panel>
            <Panel Icon={CreditCardIcon} color="#ca8a04" title="Would you pay? How much a month?" sub="price ranges among Yes + Maybe, in USD">
              <div className="fb-paybar">
                {[['yes', 'Yes', '#059669'], ['maybe', 'Maybe', '#f59e0b'], ['no', 'No', '#cbd5e1']].map(([k, l, c]) => (
                  data.would_pay[k] ? <div key={k} style={{ width: `${data.would_pay[k]}%`, background: c, color: k === 'no' ? '#475569' : '#fff' }}>{l} {data.would_pay[k]}%</div> : null
                ))}
              </div>
              <Bars color="#ca8a04" rows={data.prices.map((p) => ({ key: p.key, label: PRICE_LABELS[p.key], pct: p.pct }))}
                marks={Object.fromEntries((data.plan_prices || []).reduce((acc, p) => {
                  const cur = acc.find(([k]) => k === p.range);
                  const text = `${PLAN_LABELS[p.plan] || p.plan} $${p.usd}`;
                  if (cur) cur[1] += ` · ${text}`; else acc.push([p.range, `${text} sits here`]);
                  return acc;
                }, []))} />
              {data.would_pay.no > 0 && (
                <div className="fb-why">
                  <span className="fb-muted">Why not:</span>
                  {data.why_not.filter((w) => w.count).map((w) => <span key={w.key} className="fb-chip tone-slate">{WHY_LABELS[w.key]} {pct(w.pct)}</span>)}
                </div>
              )}
            </Panel>
          </div>

          {data.build_next_other.length > 0 && (
            <Panel Icon={MessageCircleIcon} color="#0ea5e9" title={'"Something else" ideas'} sub={`${data.build_next_other.length} written under question 3`}>
              <div className="fb-others">{data.build_next_other.map((t, i) => <span key={i} className="fb-other">{t}</span>)}</div>
            </Panel>
          )}

          <Panel Icon={QuoteIcon} color="#7c3aed" title="What people wrote" sub={`${data.comments_total} comments · badge = their 0–10 recommend score`}>
            {data.comments.length === 0 ? <div className="fb-muted">No comments yet.</div> : (
              <div className="fb-comments">
                {data.comments.map((c, i) => (
                  <div key={i} className="fb-comment">
                    <span className={`fb-score ${c.nps >= 9 ? 'pro' : c.nps <= 6 ? 'det' : 'pas'}`}>{c.nps}</span>
                    <div>
                      <div className="fb-muted">{c.name}{c.country ? ` · ${c.country}` : ''} · {formatDate(c.at)} · would pay: {c.would_pay}</div>
                      <div>{c.text}</div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </Panel>
        </>
      )}
    </div>
  );
}

// ── Settings ──────────────────────────────────────────────────────────────

const quarterName = (d = new Date()) => `Q${Math.floor(d.getMonth() / 3) + 1} ${d.getFullYear()}`;
const isoDay = (d) => d.toLocaleDateString('en-CA', { timeZone: 'Asia/Colombo' });

function RoundEditor({ round, onClose, onSaved, notify }) {
  const answered = (round?.answers || 0) > 0;
  const today = new Date();
  const [name, setName] = useState(round?.name || quarterName(today));
  const [start, setStart] = useState(round ? isoDay(new Date(round.starts_at)) : isoDay(today));
  const [end, setEnd] = useState(round ? isoDay(new Date(round.ends_at)) : isoDay(new Date(today.getTime() + 30 * 86400000)));
  const [options, setOptions] = useState(round ? round.build_next_options.map((o) => ({ ...o })) : SUGGESTED_OPTIONS.map((o) => ({ ...o })));
  const [saving, setSaving] = useState(false);
  const lockedKeys = new Set(answered ? (round.build_next_options || []).map((o) => o.key) : []);

  const set = (i, patch) => setOptions((prev) => prev.map((o, j) => (j === i ? { ...o, ...patch } : o)));
  const move = (i, dir) => setOptions((prev) => {
    const next = [...prev];
    const j = i + dir;
    if (j < 0 || j >= next.length) return prev;
    [next[i], next[j]] = [next[j], next[i]];
    return next;
  });

  const save = async () => {
    const clean = options.filter((o) => o.label?.trim());
    if (!name.trim()) { notify('Give the survey a name.', 'error'); return; }
    if (end <= start) { notify('The end date must be after the start date.', 'error'); return; }
    if (!clean.length) { notify('Add at least one "build next" option.', 'error'); return; }
    setSaving(true);
    const body = {
      name: name.trim(),
      starts_at: `${start}T00:00:00${TZ_OFFSET}`,
      ends_at: `${end}T23:59:59${TZ_OFFSET}`,
      build_next_options: clean.map((o) => ({ key: o.key || null, label: o.label.trim(), icon: o.icon || 'lightbulb' })),
    };
    try {
      if (round) await apiPatch(`/admin/survey/rounds/${round.id}`, body);
      else await apiPost('/admin/survey/rounds', body);
      notify(round ? 'Survey saved' : 'Survey created. Open it when you are ready.');
      onSaved();
    } catch (err) {
      notify(err.message || 'Could not save the survey.', 'error');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Drawer
      title={round ? `Edit ${round.name}` : 'New quarterly survey'}
      subtitle="The 5 questions are always the same. Here you set the dates and the build-next choices."
      onClose={() => !saving && onClose()}
      onSubmit={(e) => { e.preventDefault(); save(); }}
      footer={(
        <>
          <button type="button" className="btn btn-ghost" onClick={onClose}>Cancel</button>
          <button type="submit" className="btn btn-primary" disabled={saving}>{saving ? 'Saving…' : 'Save'}</button>
        </>
      )}
    >
      <div className="form-group">
        <label className="form-label" htmlFor="sv-name">Name</label>
        <input id="sv-name" className="form-input" value={name} onChange={(e) => setName(e.target.value)} maxLength={60} placeholder="Q1 2027" />
      </div>
      <div className="form-grid-2">
        <div className="form-group">
          <label className="form-label" htmlFor="sv-start">Starts</label>
          <input id="sv-start" type="date" className="form-input" value={start} onChange={(e) => setStart(e.target.value)} />
        </div>
        <div className="form-group">
          <label className="form-label" htmlFor="sv-end">Ends (end of day)</label>
          <input id="sv-end" type="date" className="form-input" value={end} onChange={(e) => setEnd(e.target.value)} />
        </div>
      </div>
      <div className="form-group">
        <label className="form-label">&ldquo;What should we build next?&rdquo; choices</label>
        <div className="fb-hint">Explorers pick up to 3, in order. {answered
          ? 'This survey has answers: you can rename or add choices, not remove them.'
          : 'Up to 15. The list below is a starting suggestion — change it freely.'}</div>
        <div className="fb-options">
          {options.map((o, i) => (
            <div key={o.key || `new-${i}`} className="fb-option">
              <select className="xp-select" value={o.icon || 'lightbulb'} onChange={(e) => set(i, { icon: e.target.value })} aria-label="Icon">
                {Object.entries(ICON_LABELS).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
              </select>
              <input className="form-input" value={o.label} maxLength={60} onChange={(e) => set(i, { label: e.target.value })} placeholder="e.g. Offline maps" />
              <button type="button" className="mbx-icon-btn" onClick={() => move(i, -1)} disabled={i === 0} title="Move up"><ArrowUpIcon size={14} /></button>
              <button type="button" className="mbx-icon-btn" onClick={() => move(i, 1)} disabled={i === options.length - 1} title="Move down"><ArrowDownIcon size={14} /></button>
              <button type="button" className="mbx-icon-btn mbx-delete" onClick={() => setOptions((prev) => prev.filter((_, j) => j !== i))}
                disabled={lockedKeys.has(o.key)} title={lockedKeys.has(o.key) ? 'Has answers, can’t be removed' : 'Remove'}><TrashIcon size={14} /></button>
            </div>
          ))}
        </div>
        {options.length < 15 && (
          <button type="button" className="btn btn-ghost btn-sm" style={{ marginTop: 8 }} onClick={() => setOptions((prev) => [...prev, { label: '', icon: 'lightbulb' }])}>
            <PlusIcon size={14} /> Add a choice
          </button>
        )}
      </div>
    </Drawer>
  );
}

export function SurveySettings({ notify }) {
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);
  const [editing, setEditing] = useState(null); // round, or {} for new
  const [busy, setBusy] = useState(null);
  const [reloads, setReloads] = useState(0);

  useEffect(() => {
    apiGet('/admin/survey/rounds').then((res) => { setData(res); setError(null); })
      .catch((err) => setError(err.message || 'Could not load surveys.'));
  }, [reloads]);

  const reload = () => setReloads((n) => n + 1);

  const toggle = async (r) => {
    const opening = !r.is_open;
    const question = opening
      ? `Open ${r.name}? Explorers start seeing it on Home${new Date(r.starts_at) > new Date() ? ` from ${formatDate(r.starts_at)}` : ' now'}. Any other open survey closes.`
      : `Close ${r.name}? It disappears from the app. Answers so far are kept.`;
    if (!window.confirm(question)) return;
    setBusy(r.id);
    try {
      await apiPatch(`/admin/survey/rounds/${r.id}`, { is_open: opening });
      notify(opening ? `${r.name} is open` : `${r.name} is closed`);
      reload();
    } catch (err) {
      notify(err.message || 'Could not change the survey.', 'error');
    } finally {
      setBusy(null);
    }
  };

  const remove = async (r) => {
    if (!window.confirm(`Delete ${r.name}? It has no answers.`)) return;
    setBusy(r.id);
    try {
      await apiDelete(`/admin/survey/rounds/${r.id}`);
      notify('Survey deleted');
      reload();
    } catch (err) {
      notify(err.message || 'Could not delete the survey.', 'error');
    } finally {
      setBusy(null);
    }
  };

  if (error) return <div className="login-error">{error}</div>;
  if (!data) return <div className="loader" />;

  return (
    <div className="fb-settings">
      <div className="fb-howto">
        <div>
          <b>How the survey reaches explorers</b>
          <ul>
            <li>While a survey is open, the Home card turns into a &ldquo;Quick survey · 1 min&rdquo; ticket.</li>
            <li>It also pops up once after 20 seconds on Home. &ldquo;Later&rdquo; hides it for 3 days; it pops up at most 3 times, never in an account&apos;s first day.</li>
            <li>Only one survey is open at a time. The 5 questions never change, so quarters can be compared.</li>
          </ul>
        </div>
        <button type="button" className="btn btn-primary" onClick={() => setEditing({})}><PlusIcon size={15} /> New survey</button>
      </div>

      {data.rounds.length === 0 ? (
        <div className="fb-empty-card"><CalendarIcon size={32} /><strong>No surveys yet</strong><p>Create one for this quarter.</p></div>
      ) : (
        <div className="fb-rounds">
          {data.rounds.map((r) => {
            const [label, cls] = stateChip(r.state);
            return (
              <div key={r.id} className="fb-round">
                <div className="fb-round-head">
                  <b>{r.name}</b>
                  <span className={`fb-status ${cls}`}>{label}</span>
                  <span className="mbx-spacer" />
                  <span className="fb-muted">{r.answers.toLocaleString()} {r.answers === 1 ? 'answer' : 'answers'}</span>
                </div>
                <div className="fb-muted">{formatDate(r.starts_at)} – {formatDate(r.ends_at)}</div>
                <div className="fb-round-options">
                  {r.build_next_options.map((o) => <span key={o.key} className="fb-chip tone-slate">{o.label}</span>)}
                </div>
                <div className="fb-round-actions">
                  <button type="button" className="btn btn-ghost btn-sm" onClick={() => setEditing(r)}><EditIcon size={14} /> Edit</button>
                  {r.state !== 'ended' && (
                    <button type="button" className={`btn btn-sm ${r.is_open ? 'btn-ghost' : 'btn-primary'}`} disabled={busy === r.id} onClick={() => toggle(r)}>
                      {r.is_open ? 'Close survey' : 'Open survey'}
                    </button>
                  )}
                  {r.answers === 0 && (
                    <button type="button" className="btn btn-ghost btn-sm mbx-delete" disabled={busy === r.id} onClick={() => remove(r)}><TrashIcon size={14} /> Delete</button>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {editing && (
        <RoundEditor round={editing.id ? editing : null} notify={notify}
          onClose={() => setEditing(null)} onSaved={() => { setEditing(null); reload(); }} />
      )}
    </div>
  );
}
