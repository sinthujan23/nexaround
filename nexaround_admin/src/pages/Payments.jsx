import { useState } from 'react';
import { apiFetch, useApi } from '../api';
import { useToast } from '../hooks';
import { PageError, PageLoading, SecretField, Toast } from '../components/Kit';
import {
  AlertTriangleIcon, CheckIcon, CreditCardIcon, CrossIcon, EditIcon, MapPinIcon, RefreshIcon, ShieldIcon,
} from '../components/Icons';
import './Payments.css';

/**
 * Payments & Plans, redesigned 2026-11-12 (layout "A"): the two go-live
 * switches sit on top and look the same; below them four tabs, one job each —
 * Money (who pays), Plans (what each plan allows), Testing (try a plan on your
 * own account), Store setup (RevenueCat keys and app versions).
 */

const PLAN = {
  explorer: { name: 'Explorer', color: '#64748b', price: 'Free', cls: 'pp-c-explorer' },
  voyager: { name: 'Voyager', color: '#007a7c', price: '$4.59 a month', cls: 'pp-c-voyager' },
  globetrotter: { name: 'Globetrotter', color: '#0b3d91', price: '$6.89 a month', cls: 'pp-c-globetrotter' },
};
const PLANS = ['explorer', 'voyager', 'globetrotter'];

// The packages document (2026-11-12); "Reset" puts these back.
const DOC_LIMITS = {
  explorer: { odyssey_per_period: 1, odyssey_max_days: 5, odyssey_lite: true, odyssey_live_prices: false, neva_per_day: 5, ar_radius_m: 2000, nearby_max_radius_m: 25000, banded_max_bands: 2, map_day_usd: 0.05, map_month_usd: 0.05, google_photos: false, discover_per_month: 3, places_source: 'open', priority_queue: false },
  voyager: { odyssey_per_period: 8, odyssey_max_days: 10, odyssey_lite: false, odyssey_live_prices: true, neva_per_day: 100, ar_radius_m: 10000, nearby_max_radius_m: 50000, banded_max_bands: 3, map_day_usd: 0, map_month_usd: 2, google_photos: true, discover_per_month: 0, places_source: 'google', priority_queue: false },
  globetrotter: { odyssey_per_period: 15, odyssey_max_days: 14, odyssey_lite: false, odyssey_live_prices: true, neva_per_day: 300, ar_radius_m: 10000, nearby_max_radius_m: 50000, banded_max_bands: 3, map_day_usd: 0, map_month_usd: 4, google_photos: true, discover_per_month: 0, places_source: 'google', priority_queue: true },
};

const WEBHOOK_URL = 'https://api.nexaround.com/api/v1/billing/revenuecat';

const usd = (v) => `$${Number(v || 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const day = (v) => (v ? new Date(v).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : '');
const when = (v) => (v ? new Date(v).toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '');
const emailsOf = (s) => (s || '').split(',').map((e) => e.trim()).filter(Boolean);

function PlanPill({ plan, suffix }) {
  const p = PLAN[plan] || PLAN.explorer;
  return <span className="pp-pill" style={{ background: p.color }}>{p.name}{suffix ? ` · ${suffix}` : ''}</span>;
}

/** The same Off / Test / Everyone control for both switches. */
function Choice({ value, options, onChange }) {
  return (
    <div className="pp-seg" role="radiogroup">
      {options.map(([k, label]) => (
        <button key={k} role="radio" aria-checked={value === k}
          className={`pp-seg-btn ${value === k ? `active ${k}` : ''}`} onClick={() => value !== k && onChange(k)}>
          {label}
        </button>
      ))}
    </div>
  );
}

export default function Payments() {
  const [toast, notify] = useToast();
  const [tab, setTab] = useState('money');
  const overview = useApi('/admin/billing/overview');
  const settings = useApi('/admin/billing/settings');

  if ((overview.loading && !overview.data) || (settings.loading && !settings.data)) return <PageLoading />;
  if (overview.error && !overview.data) return <PageError error={overview.error} onRetry={overview.refetch} />;
  if (settings.error && !settings.data) return <PageError error={settings.error} onRetry={settings.refetch} />;
  const o = overview.data || {};
  const s = settings.data || {};

  const save = async (body, message) => {
    try {
      await apiFetch('/admin/billing/settings', { method: 'PUT', body: JSON.stringify(body) });
      notify(message || 'Saved');
      settings.refetch();
      overview.refetch();
      return true;
    } catch (e) {
      notify(e.message, 'error');
      return false;
    }
  };

  const tabs = [
    ['money', 'Money', o.subscribers ?? 0],
    ['plans', 'Plans'],
    ['testing', 'Testing'],
    ['setup', 'Store setup'],
  ];

  return (
    <div>
      <Toast toast={toast} />
      <div className="pp-head">
        <h2>Payments &amp; Plans</h2>
        <p>Explorer (free) · Voyager $4.59 · Globetrotter $6.89 a month. People pay in the app through Apple or Google.</p>
      </div>

      <Switches s={s} save={save} />

      <div className="segmented-tabs pp-tabs" role="tablist">
        {tabs.map(([key, label, count]) => (
          <button key={key} role="tab" className={`segmented-tab ${tab === key ? 'active' : ''}`} onClick={() => setTab(key)}>
            {label}
            {count !== undefined && <span className="tab-count">{count}</span>}
          </button>
        ))}
      </div>

      {tab === 'money' && <MoneyTab o={o} notify={notify} onChanged={overview.refetch} />}
      {tab === 'plans' && <PlansTab o={o} s={s} save={save} />}
      {tab === 'testing' && <TestTab s={s} save={save} notify={notify} onChanged={overview.refetch} />}
      {tab === 'setup' && <SetupTab s={s} save={save} notify={notify} />}
    </div>
  );
}

/* ── Go-live switches ─────────────────────────────────────────────────── */

function Switches({ s, save }) {
  const fd = useApi('/admin/billing/free-data');
  const d = fd.data || {};
  const areas = d.areas || {};
  const totalAreas = (areas.done || 0) + (areas.queued || 0) + (areas.importing || 0) + (areas.failed || 0);

  const limitsMode = s.plans_enforce ? 'on' : 'test';
  const freeMode = s.free_data_layer || 'off';

  const setLimits = (m) => {
    const on = m === 'on';
    const ok = window.confirm(on
      ? 'Plan limits for EVERYONE?\n\nFree users get Explorer limits right away; subscribers get their plan. Do this on the day the new app is released.'
      : 'Plan limits for TEST ACCOUNTS ONLY?\n\nEveryone else gets unlimited use again.');
    if (ok) save({ plans_enforce: on }, on ? 'Plan limits: everyone' : 'Plan limits: test accounts only');
  };

  const setFree = async (m) => {
    if (m === 'on' && !window.confirm('Free map data for ALL free users?\n\nFree users on the new app get food, shop, hotel and medical places from free map data, without Google ratings. Paid users and older app versions keep Google. You can switch it back at any time.')) return;
    const label = { off: 'off', test: 'test accounts only', on: 'everyone' }[m];
    if (await save({ free_data_layer: m }, `Free map data: ${label}`)) fd.refetch();
  };

  return (
    <div className="pp-card pp-switches">
      <div className="pp-switches-title">Go-live switches</div>

      <div className="pp-switch-row">
        <div className={`pp-switch-icon ${limitsMode}`}><ShieldIcon size={18} /></div>
        <div className="pp-switch-text">
          <b>Plan limits</b>
          <span>
            {limitsMode === 'on'
              ? 'Everyone has plan limits: free users get Explorer, subscribers get their plan.'
              : 'Only test accounts have limits. Everyone else has unlimited use.'}
          </span>
        </div>
        <Choice value={limitsMode} onChange={setLimits}
          options={[['test', 'Test accounts only'], ['on', 'Everyone']]} />
      </div>

      <div className="pp-switch-row">
        <div className={`pp-switch-icon ${freeMode}`}><MapPinIcon size={18} /></div>
        <div className="pp-switch-text">
          <b>Free map data</b>
          <span>
            {freeMode === 'off' && 'Everyone gets places from Google, as before.'}
            {freeMode === 'test' && 'Test accounts on the new app get food, shop, hotel and medical places from free map data.'}
            {freeMode === 'on' && 'Free users on the new app get food, shop, hotel and medical places from free map data. Paid users keep Google.'}
          </span>
          <span className="pp-switch-meta">
            {areas.done ?? 0} of {totalAreas} cities ready · {(d.places ?? 0).toLocaleString()} places
            {' · '}Geoapify {d.geoapify_credits_today ?? 0} of {d.geoapify_daily_cap ?? 2700} today
            {' · '}app {s.free_data_min_app_version || '1.0.18'}+
            {areas.failed ? ` · ${areas.failed} failed` : ''}
          </span>
        </div>
        <Choice value={freeMode} onChange={setFree}
          options={[['off', 'Off'], ['test', 'Test accounts only'], ['on', 'Everyone']]} />
      </div>

      <div className="pp-switches-foot">Test accounts are set in the <b>Testing</b> tab.</div>
    </div>
  );
}

/* ── Money ────────────────────────────────────────────────────────────── */

const EVENT = {
  INITIAL_PURCHASE: ['New subscription', CheckIcon],
  RENEWAL: ['Renewed', RefreshIcon],
  PRODUCT_CHANGE: ['Changed plan', RefreshIcon],
  CANCELLATION: ['Cancelled (keeps the plan until the period ends)', CrossIcon],
  UNCANCELLATION: ['Turned renewal back on', CheckIcon],
  EXPIRATION: ['Plan ended', CrossIcon],
  BILLING_ISSUE: ['Payment problem', AlertTriangleIcon],
  TEST: ['Test message from RevenueCat', CheckIcon],
};

function MoneyTab({ o, notify, onChanged }) {
  const events = useApi('/admin/billing/events?limit=10');
  return (
    <div className="pp-section">
      <div className="pp-grid-4">
        <Kpi value={o.subscribers ?? 0} label="Paying subscribers" />
        <Kpi value={usd(o.mrr_usd)} label="Monthly revenue (estimate)" />
        <Kpi value={usd(o.revenue_month_usd)} label="Charged this month" />
        <Kpi value={o.cancellations_30d ?? 0} label="Cancelled in the last 30 days" />
      </div>

      <SubscribersCard notify={notify} onChanged={onChanged} />

      <div className="pp-card">
        <h3>Latest activity</h3>
        <p className="pp-sub">Purchases, renewals and cancellations from the App Store and Google Play. “Test” = no real money.</p>
        {(events.data || []).length === 0 ? (
          <div className="pp-empty">Nothing yet. Purchases show here within seconds.</div>
        ) : (
          <div className="pp-activity">
            {events.data.map((e) => {
              const [text, Icon] = EVENT[e.type] || [e.type.replaceAll('_', ' ').toLowerCase(), CreditCardIcon];
              return (
                <div key={e.event_id} className="pp-activity-item">
                  <div className="pp-activity-icon"><Icon size={15} style={{ color: 'var(--accent)' }} /></div>
                  <div>
                    <div className="pp-activity-text">
                      <strong>{text}</strong>{e.email ? ` — ${e.email}` : ''}
                      {e.environment === 'SANDBOX' && <span className="pp-tag blue" style={{ marginLeft: 8 }}>Test</span>}
                    </div>
                    <div className="pp-activity-meta">
                      {when(e.event_at)}{e.product_id ? ` · ${e.product_id}` : ''}{e.price_usd != null ? ` · ${usd(e.price_usd)}` : ''}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

function Kpi({ value, label }) {
  return (
    <div className="pp-card pp-kpi">
      <div className="v">{value}</div>
      <div className="l">{label}</div>
    </div>
  );
}

const STATUS = {
  active: ['Active', 'green'],
  cancelled: ['Cancelled — ends on its date', 'yellow'],
  billing_issue: ['Payment problem', 'red'],
  expired: ['Ended', ''],
};

function SubscribersCard({ notify, onChanged }) {
  const [status, setStatus] = useState('active');
  const [plan, setPlan] = useState('');
  const [search, setSearch] = useState('');
  const subs = useApi(`/admin/billing/subscriptions?status=${status}&page_size=100${plan ? `&plan=${plan}` : ''}${search ? `&search=${encodeURIComponent(search)}` : ''}`);
  const items = subs.data?.items || [];

  const backToExplorer = async (row) => {
    if (!window.confirm(`Take the hand-given ${PLAN[row.plan]?.name} plan away from ${row.email}?`)) return;
    try {
      await apiFetch(`/admin/billing/grant/${row.user_id}`, { method: 'DELETE' });
      notify(`${row.email} is back on Explorer`);
      subs.refetch();
      onChanged();
    } catch (e) {
      notify(e.message, 'error');
    }
  };

  return (
    <div className="pp-card">
      <div className="pp-card-head">
        <h3>Subscribers</h3>
        <input className="form-input" placeholder="Search name or email" value={search}
          onChange={(e) => setSearch(e.target.value)} style={{ width: 220 }} />
      </div>
      <div className="pp-filters">
        {[['active', 'Active'], ['ended', 'Ended'], ['all', 'All']].map(([k, l]) => (
          <button key={k} className={`pp-chip ${status === k ? 'active' : ''}`} onClick={() => setStatus(k)}>{l}</button>
        ))}
        <span className="pp-divider" />
        {[['', 'All plans'], ['voyager', 'Voyager'], ['globetrotter', 'Globetrotter']].map(([k, l]) => (
          <button key={k || 'all'} className={`pp-chip ${plan === k ? 'active' : ''}`} onClick={() => setPlan(k)}>{l}</button>
        ))}
      </div>

      {subs.loading && !subs.data ? <div className="pp-empty">Loading…</div> : items.length === 0 ? (
        <div className="pp-empty">No one here yet. People who subscribe in the app, or get a plan in the Testing tab, appear here.</div>
      ) : (
        <div className="table-wrap">
          <table>
            <thead><tr><th>Person</th><th>Plan</th><th>Status</th><th>Until</th><th>How they got it</th><th /></tr></thead>
            <tbody>
              {items.map((r) => {
                const [label, tone] = STATUS[r.status] || [r.status, ''];
                return (
                  <tr key={`${r.user_id}-${r.source}`}>
                    <td>
                      <div className="pp-person">
                        <div className="pp-avatar">{(r.name || r.email || '?')[0].toUpperCase()}</div>
                        <div><div className="n">{r.name || '—'}</div><div className="e">{r.email}</div></div>
                      </div>
                    </td>
                    <td><PlanPill plan={r.plan} /></td>
                    <td>
                      <span className={`pp-tag ${tone}`}>{label}</span>
                      {r.environment === 'SANDBOX' && <span className="pp-tag blue" style={{ marginLeft: 6 }}>Test</span>}
                    </td>
                    <td>{r.period_end ? day(r.period_end) : 'No end date'}</td>
                    <td>{r.source === 'admin' ? `Given here by ${r.granted_by || 'admin'}` : r.store === 'app_store' ? 'Bought on App Store' : r.store === 'play_store' ? 'Bought on Google Play' : 'Bought in the app'}</td>
                    <td style={{ textAlign: 'right' }}>
                      {r.source === 'admin' && r.status !== 'expired' && (
                        <button className="btn btn-ghost pp-btn-sm" onClick={() => backToExplorer(r)}>Back to Explorer</button>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

/* ── Plans ────────────────────────────────────────────────────────────── */

// [key, label, hint, kind]; kind: num | days | km | bands | usd | a key of TOGGLES
const LIMIT_GROUPS = [
  ['Odyssey trip planner', [
    ['odyssey_per_period', 'Plans a month', 'Free: resets on the 1st. Paid: on their billing day.', 'num'],
    ['odyssey_max_days', 'Longest trip', '', 'days'],
    ['odyssey_lite', 'Ratings & opening hours', '“Hidden” = Lite plan', 'lite'],
    ['odyssey_live_prices', 'Flight & hotel prices', '“Estimated” = no live price search', 'live'],
    ['priority_queue', 'Priority queue', 'Plans start first when it is busy', 'yesno'],
  ]],
  ['Neva & Where Should I Go', [
    ['neva_per_day', 'Neva messages a day', 'Resets at midnight UTC', 'num'],
    ['discover_per_month', 'Where Should I Go a month', '0 = unlimited', 'num'],
  ]],
  ['Map, Around You & AR', [
    ['ar_radius_m', 'AR range', 'Hospitals are never limited', 'km'],
    ['nearby_max_radius_m', 'Around You reach', 'Medical / Hospital always full range', 'km'],
    ['banded_max_bands', 'Around You distance bands', '3 = all bands', 'bands'],
    ['google_photos', 'Place photos', '“Saved only” = photos we already hold', 'photos'],
    ['map_day_usd', 'Google map data a day', '0 = no daily limit', 'usd'],
    ['map_month_usd', 'Google map data a month', '0 = no monthly limit', 'usd'],
  ]],
];

// Boolean limits: [label when true, label when false, true is the "good" state]
const TOGGLES = {
  lite: ['Hidden', 'Shown', false],
  yesno: ['Yes', 'No', true],
  live: ['Live', 'Estimated', true],
  photos: ['All photos', 'Saved only', true],
};

function PlansTab({ o, s, save }) {
  const limits = s.plan_limits || DOC_LIMITS;
  const byPlan = o.by_plan || {};
  const [editing, setEditing] = useState(null);

  const resetAll = async () => {
    if (!window.confirm('Put every plan back to the packages document?\n\nThis also switches on the new free limits (saved photos only, estimated Odyssey prices, Where Should I Go 3 a month, $0.05 Google map data).')) return;
    await save({ plan_limits: DOC_LIMITS }, 'All plans match the packages document');
  };

  return (
    <div className="pp-section">
      <div className="pp-grid-3">
        {PLANS.map((p) => {
          const l = { ...DOC_LIMITS[p], ...(limits[p] || {}) };
          const b = byPlan[p] || {};
          return (
            <div key={p} className="pp-plan">
              <div className={`pp-plan-head ${PLAN[p].cls}`}>
                <div className="name">{PLAN[p].name}</div>
                <div className="price">{PLAN[p].price}</div>
                <div className="who">
                  {p === 'explorer' ? 'Everyone who hasn’t paid' : `${b.total ?? 0} ${(b.total ?? 0) === 1 ? 'subscriber' : 'subscribers'}`}
                </div>
              </div>
              <div className="pp-plan-body">
                <div className="pp-row"><span>Odyssey plans</span><span>{l.odyssey_per_period} a month{l.odyssey_lite ? ' (Lite)' : ''}</span></div>
                <div className="pp-row"><span>Longest trip</span><span>{l.odyssey_max_days} days</span></div>
                <div className="pp-row"><span>Neva</span><span>{l.neva_per_day} a day</span></div>
                <div className="pp-row"><span>Where Should I Go</span><span>{l.discover_per_month > 0 ? `${l.discover_per_month} a month` : 'Unlimited'}</span></div>
                <div className="pp-row"><span>AR range</span><span>{Math.round(l.ar_radius_m / 1000)} km</span></div>
                <div className="pp-row"><span>Photos</span><span>{l.google_photos ? 'All' : 'Saved only'}</span></div>
                <button className="btn btn-ghost pp-edit" onClick={() => setEditing(p)}>
                  <EditIcon size={14} /> Edit {PLAN[p].name}
                </button>
              </div>
            </div>
          );
        })}
      </div>
      <div className="pp-muted pp-center">
        Changes reach the app within a minute, no app update needed.{' '}
        <button className="pp-link" onClick={resetAll}>Reset all plans to the packages document</button>
      </div>

      {editing && (
        <PlanEditor plan={editing} limits={limits} onClose={() => setEditing(null)}
          onSave={async (values) => {
            if (await save({ plan_limits: { ...limits, [editing]: values } }, `${PLAN[editing].name} saved`)) setEditing(null);
          }} />
      )}
    </div>
  );
}

function PlanEditor({ plan, limits, onClose, onSave }) {
  const [form, setForm] = useState(() => ({ ...DOC_LIMITS[plan], ...(limits[plan] || {}) }));
  const set = (k, v) => setForm((f) => ({ ...f, [k]: v }));

  const control = (k, kind) => {
    const v = form[k];
    if (TOGGLES[kind]) {
      const [onLabel, offLabel] = TOGGLES[kind];
      return <Choice value={v ? 'y' : 'n'} onChange={(x) => set(k, x === 'y')} options={[['y', onLabel], ['n', offLabel]]} />;
    }
    const unit = { days: 'days', km: 'km', bands: 'bands', num: '' }[kind];
    const val = kind === 'km' ? (v || 0) / 1000 : v;
    return (
      <span className="pp-num">
        {kind === 'usd' && <em>$</em>}
        <input className="form-input" type="number" min="0" step={kind === 'usd' ? '0.01' : kind === 'km' ? '0.5' : '1'}
          value={val ?? ''} onChange={(e) => {
            const n = e.target.value === '' ? 0 : Number(e.target.value);
            set(k, kind === 'km' ? Math.round(n * 1000) : n);
          }} />
        {unit && <em>{unit}</em>}
      </span>
    );
  };

  return (
    <>
      <div className="pp-backdrop" onClick={onClose} />
      <aside className="pp-drawer" role="dialog" aria-label={`Edit ${PLAN[plan].name}`}>
        <div className={`pp-drawer-head ${PLAN[plan].cls}`}>
          <div>
            <div className="name">{PLAN[plan].name}</div>
            <div className="price">{PLAN[plan].price}</div>
          </div>
          <button className="pp-close" onClick={onClose} aria-label="Close">×</button>
        </div>
        <div className="pp-drawer-body">
          {LIMIT_GROUPS.map(([group, rows]) => (
            <div key={group} className="pp-drawer-group">
              <div className="pp-label">{group}</div>
              {rows.map(([k, label, hint, kind]) => (
                <div key={k} className="pp-field">
                  <div>
                    <div className="t">{label}</div>
                    {hint && <div className="h">{hint}</div>}
                  </div>
                  {control(k, kind)}
                </div>
              ))}
            </div>
          ))}
        </div>
        <div className="pp-drawer-foot">
          <button className="btn btn-ghost" onClick={() => setForm({ ...DOC_LIMITS[plan] })}>Use the packages document</button>
          <button className="btn btn-primary" onClick={() => onSave(form)}>Save {PLAN[plan].name}</button>
        </div>
      </aside>
    </>
  );
}

/* ── Testing ──────────────────────────────────────────────────────────── */

const DURATIONS = [['1', '1 day'], ['7', '7 days'], ['30', '30 days'], ['', 'No end']];

function TestTab({ s, save, notify, onChanged }) {
  const testers = emailsOf(s.plans_enforce_users);
  const [newEmail, setNewEmail] = useState('');
  const [email, setEmail] = useState(testers[0] || '');
  const [plan, setPlan] = useState('voyager');
  const [days, setDays] = useState('1');
  const [busy, setBusy] = useState(false);
  const given = useApi('/admin/billing/subscriptions?status=active&page_size=100');
  const grants = (given.data?.items || []).filter((r) => r.source === 'admin');

  const setTesters = (list, message) => save({ plans_enforce_users: list.join(', ') }, message);

  const addTester = async () => {
    const e = newEmail.trim().toLowerCase();
    if (!e || !e.includes('@')) return notify('Type a full email address', 'error');
    if (testers.map((t) => t.toLowerCase()).includes(e)) return notify('Already a test account', 'error');
    if (await setTesters([...testers, e], `${e} added as a test account`)) {
      setNewEmail('');
      if (!email) setEmail(e);
    }
  };

  const removeGrant = async (g) => {
    try {
      await apiFetch(`/admin/billing/grant/${g.user_id}`, { method: 'DELETE' });
      notify(`${g.email} is back on Explorer`);
      given.refetch();
      onChanged();
    } catch (e) { notify(e.message, 'error'); }
  };

  const apply = async () => {
    const target = email.trim().toLowerCase();
    if (!target) return notify('Choose or type an email first', 'error');
    setBusy(true);
    try {
      if (plan === 'explorer') {
        const res = await apiFetch(`/admin/billing/subscriptions?status=all&page_size=100&search=${encodeURIComponent(target)}`);
        const row = (res.items || []).find((r) => r.source === 'admin' && (r.email || '').toLowerCase() === target);
        if (!row) {
          notify(`${target} has no hand-given plan — already Explorer (unless they paid in the app)`);
        } else {
          await apiFetch(`/admin/billing/grant/${row.user_id}`, { method: 'DELETE' });
          notify(`${target} is now on Explorer`);
        }
      } else {
        await apiFetch('/admin/billing/grant', {
          method: 'POST',
          body: JSON.stringify({ email: target, plan, days: days ? Number(days) : null, note: 'Test from admin' }),
        });
        notify(`${target} is now on ${PLAN[plan].name}${days ? ` for ${days} day${days === '1' ? '' : 's'}` : ''}`);
      }
      given.refetch();
      onChanged();
    } catch (e) {
      notify(e.message, 'error');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="pp-section pp-grid-2">
      <div className="pp-card">
        <h3>Test accounts</h3>
        <p className="pp-sub">These accounts get plan limits and free map data when a switch is set to “Test accounts only”. Nobody pays.</p>
        <div className="pp-emails">
          {testers.length === 0 && <span className="pp-muted">No test accounts yet.</span>}
          {testers.map((t) => (
            <span key={t} className="pp-email-chip">
              {t}
              <button title="Remove" onClick={() => setTesters(testers.filter((x) => x !== t), `${t} removed`)}>×</button>
            </span>
          ))}
        </div>
        <div className="pp-inline">
          <input className="form-input" type="email" placeholder="name@example.com" value={newEmail}
            onChange={(e) => setNewEmail(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && addTester()} style={{ flex: '1 1 200px' }} />
          <button className="btn btn-primary" onClick={addTester}>Add</button>
        </div>

        <div className="pp-label" style={{ marginTop: 22 }}>Plans given by hand</div>
        {grants.length === 0 ? <div className="pp-muted">None right now.</div> : (
          <div className="pp-activity">
            {grants.map((g) => (
              <div key={g.user_id} className="pp-activity-item" style={{ alignItems: 'center' }}>
                <div className="pp-avatar">{(g.name || g.email || '?')[0].toUpperCase()}</div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div className="pp-activity-text"><strong>{g.email}</strong> <PlanPill plan={g.plan} /></div>
                  <div className="pp-activity-meta">{g.period_end ? `Ends ${when(g.period_end)}` : 'No end date'}</div>
                </div>
                <button className="btn btn-ghost pp-btn-sm" onClick={() => removeGrant(g)}>Back to Explorer</button>
              </div>
            ))}
          </div>
        )}
      </div>

      <div className="pp-card">
        <h3>Give a plan</h3>
        <p className="pp-sub">Try any plan on any account, then reopen the app. A plan bought in the app is never touched.</p>

        <div className="pp-label">Account</div>
        <input className="form-input" list="pp-testers" type="email" placeholder="Email of the account" value={email}
          onChange={(e) => setEmail(e.target.value)} style={{ width: '100%' }} />
        <datalist id="pp-testers">{testers.map((t) => <option key={t} value={t} />)}</datalist>

        <div className="pp-label">Plan</div>
        <div className="pp-choice-grid">
          {PLANS.map((p) => (
            <button key={p} className={`pp-choice ${plan === p ? 'active' : ''}`} onClick={() => setPlan(p)}>
              <div className="t"><span className="pp-swatch" style={{ background: PLAN[p].color }} />{PLAN[p].name}</div>
              <div className="d">{p === 'explorer' ? 'Back to free' : PLAN[p].price}</div>
            </button>
          ))}
        </div>

        {plan !== 'explorer' && (
          <>
            <div className="pp-label">For how long</div>
            <div className="pp-inline">
              {DURATIONS.map(([v, l]) => (
                <button key={l} className={`pp-chip ${days === v ? 'active' : ''}`} onClick={() => setDays(v)}>{l}</button>
              ))}
            </div>
          </>
        )}

        <div className="pp-actions">
          <button className="btn btn-primary" disabled={busy} onClick={apply}>
            {busy ? 'Saving…' : plan === 'explorer' ? 'Move to Explorer' : `Give ${PLAN[plan].name}`}
          </button>
        </div>
      </div>
    </div>
  );
}

/* ── Store setup ──────────────────────────────────────────────────────── */

function SetupTab({ s, save, notify }) {
  const [ios, setIos] = useState(s.revenuecat_ios_key || '');
  const [android, setAndroid] = useState(s.revenuecat_android_key || '');
  const [secret, setSecret] = useState('');
  const [hook, setHook] = useState('');
  const [minVersion, setMinVersion] = useState(s.min_app_version || '');
  const [freeVersion, setFreeVersion] = useState(s.free_data_min_app_version || '');

  const checks = [
    ['App Store key (appl_…)', !!s.revenuecat_ios_key],
    ['Google Play key (goog_…)', !!s.revenuecat_android_key],
    ['RevenueCat secret key (sk_…, V1)', !!s.revenuecat_api_key_set],
    ['Webhook password', !!s.revenuecat_webhook_secret_set],
  ];
  const done = checks.filter(([, ok]) => ok).length;

  const saveKeys = async () => {
    const body = { revenuecat_ios_key: ios.trim(), revenuecat_android_key: android.trim() };
    if (secret.trim()) body.revenuecat_api_key = secret.trim();
    if (hook.trim()) body.revenuecat_webhook_secret = hook.trim();
    if (await save(body, 'Store keys saved')) {
      setSecret('');
      setHook('');
    }
  };

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(WEBHOOK_URL);
      notify('Webhook address copied');
    } catch {
      notify('Copy failed — select the address and copy it', 'error');
    }
  };

  return (
    <div className="pp-section">
      <div className="pp-card">
        <div className="pp-card-head">
          <h3>Connection to the stores</h3>
          <span className={`pp-tag ${done === checks.length ? 'green' : 'yellow'}`}>{done} of {checks.length} done</span>
        </div>
        <p className="pp-sub">Values come from RevenueCat (Project settings → API keys). Purchases work once all four are done.</p>
        <div className="pp-checks">
          {checks.map(([label, ok]) => (
            <div key={label} className="pp-check">
              <div className="lbl"><span className={`pp-tick ${ok ? 'ok' : 'no'}`}>{ok ? '✓' : ''}</span>{label}</div>
              <span className={`pp-tag ${ok ? 'green' : ''}`}>{ok ? 'Connected' : 'Not set'}</span>
            </div>
          ))}
        </div>

        <div className="pp-label">Webhook address (RevenueCat → Integrations → Webhooks)</div>
        <div className="pp-code">
          {WEBHOOK_URL}
          <button className="btn btn-ghost pp-btn-sm" onClick={copy}>Copy</button>
        </div>

        <div className="pp-label">Keys</div>
        <div className="pp-form-grid">
          <div className="form-group">
            <label className="form-label">App Store key (appl_…)</label>
            <input className="form-input" value={ios} onChange={(e) => setIos(e.target.value)} placeholder="appl_…" />
          </div>
          <div className="form-group">
            <label className="form-label">Google Play key (goog_…)</label>
            <input className="form-input" value={android} onChange={(e) => setAndroid(e.target.value)} placeholder="goog_…" />
          </div>
          <SecretField label="RevenueCat secret key (sk_…)" tag={s.revenuecat_api_key_set ? 'SET — leave empty to keep' : 'NOT SET'}
            value={secret} onChange={setSecret} placeholder="sk_…" />
          <SecretField label="Webhook password" tag={s.revenuecat_webhook_secret_set ? 'SET — leave empty to keep' : 'NOT SET'}
            value={hook} onChange={setHook} placeholder="Same as RevenueCat's Authorization header" />
        </div>
        <div className="pp-actions">
          <button className="btn btn-primary" onClick={saveKeys}>Save keys</button>
        </div>
      </div>

      <div className="pp-card">
        <h3>App versions</h3>
        <p className="pp-sub">Set these on release day.</p>
        <div className="pp-form-grid">
          <div className="form-group">
            <label className="form-label">Oldest app version allowed</label>
            <input className="form-input" value={minVersion} onChange={(e) => setMinVersion(e.target.value)} placeholder="e.g. 1.0.18 — empty = no minimum" />
            <span className="pp-muted">Older versions are asked to update.</span>
          </div>
          <div className="form-group">
            <label className="form-label">Free map data needs version</label>
            <input className="form-input" value={freeVersion} onChange={(e) => setFreeVersion(e.target.value)} placeholder="1.0.18" />
            <span className="pp-muted">Older versions keep Google places.</span>
          </div>
        </div>
        <div className="pp-actions">
          <button className="btn btn-primary"
            onClick={() => save({ min_app_version: minVersion.trim(), free_data_min_app_version: freeVersion.trim() }, 'App versions saved')}>
            Save versions
          </button>
        </div>
      </div>
    </div>
  );
}
