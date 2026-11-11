import { useState } from 'react';
import { apiFetch, useApi } from '../api';
import { useToast } from '../hooks';
import { PageError, PageLoading, SecretField, Toast } from '../components/Kit';
import { AlertTriangleIcon, CheckIcon, CreditCardIcon, CrossIcon, RefreshIcon } from '../components/Icons';
import './Payments.css';

/**
 * Payments & Plans. Payment happens in the app (Apple / Google, through
 * RevenueCat); this page shows who pays, lets the team test any plan on their
 * own account, and holds the plan settings — in plain words, one job per tab.
 */

const PLAN = {
  explorer: { name: 'Explorer', color: '#64748b', price: 'Free', cls: 'pp-c-explorer' },
  voyager: { name: 'Voyager', color: '#007a7c', price: '$4.59 a month · $45.99 a year', cls: 'pp-c-voyager' },
  globetrotter: { name: 'Globetrotter', color: '#0b3d91', price: '$6.89 a month · $68.99 a year', cls: 'pp-c-globetrotter' },
};
const PLANS = ['explorer', 'voyager', 'globetrotter'];

// The packages document (2026-11-10); "Reset" puts these back.
const DOC_LIMITS = {
  explorer: { odyssey_per_period: 1, odyssey_max_days: 5, odyssey_lite: true, neva_per_day: 20, ar_radius_m: 2000, nearby_max_radius_m: 25000, banded_max_bands: 2, map_day_usd: 0.15, map_month_usd: 0.5, priority_queue: false },
  voyager: { odyssey_per_period: 8, odyssey_max_days: 10, odyssey_lite: false, neva_per_day: 100, ar_radius_m: 10000, nearby_max_radius_m: 50000, banded_max_bands: 3, map_day_usd: 0, map_month_usd: 2, priority_queue: false },
  globetrotter: { odyssey_per_period: 15, odyssey_max_days: 14, odyssey_lite: false, neva_per_day: 300, ar_radius_m: 10000, nearby_max_radius_m: 50000, banded_max_bands: 3, map_day_usd: 0, map_month_usd: 4, priority_queue: true },
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

export default function Payments() {
  const [toast, notify] = useToast();
  const [tab, setTab] = useState('overview');
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

  const toggleEveryone = () => {
    const turningOn = !s.plans_enforce;
    const ok = window.confirm(turningOn
      ? 'Turn plan limits ON for everyone?\n\nFree users will get Explorer limits right away. Do this on the day the new app (with the plans screen) is released.'
      : 'Turn plan limits OFF for everyone?\n\nEveryone gets unlimited use again. Test accounts keep their limits.');
    if (ok) save({ plans_enforce: turningOn }, turningOn ? 'Plan limits are now ON for everyone' : 'Plan limits are now OFF');
  };

  const tabs = [
    ['overview', 'Overview'],
    ['subscribers', 'Subscribers'],
    ['test', 'Test a plan'],
    ['limits', 'Limits'],
    ['setup', 'Store setup'],
  ];

  return (
    <div>
      <Toast toast={toast} />
      <div className="pp-hero">
        <div>
          <h2>Payments &amp; Plans</h2>
          <p>Explorer (free) · Voyager · Globetrotter. People pay in the app through Apple or Google.</p>
        </div>
        <span className="pp-status">
          <span className={`pp-dot ${s.plans_enforce ? 'on' : ''}`} />
          {s.plans_enforce ? 'Limits ON for everyone' : 'Limits OFF (testing only)'}
        </span>
      </div>

      <div className="segmented-tabs pp-tabs" role="tablist">
        {tabs.map(([key, label]) => (
          <button key={key} role="tab" className={`segmented-tab ${tab === key ? 'active' : ''}`} onClick={() => setTab(key)}>
            {label}
            {key === 'subscribers' && <span className="tab-count">{o.subscribers ?? 0}</span>}
          </button>
        ))}
      </div>

      {tab === 'overview' && <OverviewTab o={o} s={s} onToggle={toggleEveryone} />}
      {tab === 'subscribers' && <SubscribersTab notify={notify} onChanged={overview.refetch} />}
      {tab === 'test' && <TestTab s={s} save={save} notify={notify} onChanged={overview.refetch} />}
      {tab === 'limits' && <LimitsTab s={s} save={save} />}
      {tab === 'setup' && <SetupTab s={s} save={save} notify={notify} />}
    </div>
  );
}

/* ── Overview ─────────────────────────────────────────────────────────── */

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

function OverviewTab({ o, s, onToggle }) {
  const events = useApi('/admin/billing/events?limit=12');
  const limits = s.plan_limits || DOC_LIMITS;
  const byPlan = o.by_plan || {};

  return (
    <div className="pp-section">
      <div className={`pp-card pp-switch-card ${s.plans_enforce ? 'on' : 'off'}`}>
        <div>
          <h3>{s.plans_enforce ? 'Plan limits are ON for everyone' : 'Plan limits are OFF — everyone has unlimited use'}</h3>
          <p className="pp-sub" style={{ margin: 0 }}>
            {s.plans_enforce
              ? 'Free users get Explorer limits; subscribers get their plan.'
              : 'Only your test accounts (Test a plan tab) get limits. Turn this on the day the new app is released.'}
          </p>
        </div>
        <button className={`btn ${s.plans_enforce ? 'btn-ghost' : 'btn-primary'}`} onClick={onToggle}>
          {s.plans_enforce ? 'Turn off' : 'Turn on for everyone'}
        </button>
      </div>

      <div className="pp-grid-4">
        <Kpi value={o.subscribers ?? 0} label="Paying subscribers" />
        <Kpi value={usd(o.mrr_usd)} label="Monthly revenue (estimate)" />
        <Kpi value={usd(o.revenue_month_usd)} label="Charged this month" />
        <Kpi value={o.cancellations_30d ?? 0} label="Cancelled in the last 30 days" />
      </div>

      <div className="pp-grid-3">
        {PLANS.map((p) => {
          const l = limits[p] || DOC_LIMITS[p];
          const b = byPlan[p] || {};
          return (
            <div key={p} className="pp-plan">
              <div className={`pp-plan-head ${PLAN[p].cls}`}>
                <div className="name">{PLAN[p].name}</div>
                <div className="price">{PLAN[p].price}</div>
                {p === 'explorer'
                  ? <div className="count" style={{ fontSize: 16, marginTop: 14 }}>Everyone who hasn't paid</div>
                  : <div className="count">{b.total ?? 0}<small>{b.monthly ?? 0} monthly · {b.yearly ?? 0} yearly</small></div>}
              </div>
              <div className="pp-plan-body">
                <div className="pp-row"><span>Odyssey plans a month</span><span>{l.odyssey_per_period}{l.odyssey_lite ? ' Lite' : ''}</span></div>
                <div className="pp-row"><span>Longest trip</span><span>{l.odyssey_max_days} days</span></div>
                <div className="pp-row"><span>Neva messages a day</span><span>{l.neva_per_day}</span></div>
                <div className="pp-row"><span>AR range</span><span>{Math.round(l.ar_radius_m / 1000)} km</span></div>
                <div className="pp-row"><span>Around You</span><span>{l.banded_max_bands >= 3 ? 'All 3 bands' : `Nearest ${l.banded_max_bands} bands`}</span></div>
                <div className="pp-row"><span>Priority queue</span><span>{l.priority_queue ? 'Yes' : 'No'}</span></div>
              </div>
            </div>
          );
        })}
      </div>

      <div className="pp-card">
        <h3>Latest activity</h3>
        <p className="pp-sub">Every purchase, renewal and cancellation from the App Store and Google Play. “Test” = a test purchase, not real money.</p>
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

/* ── Subscribers ──────────────────────────────────────────────────────── */

const STATUS = {
  active: ['Active', 'green'],
  cancelled: ['Cancelled — ends on its date', 'yellow'],
  billing_issue: ['Payment problem', 'red'],
  expired: ['Ended', ''],
};

function SubscribersTab({ notify, onChanged }) {
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
      <div className="pp-filters">
        {[['active', 'Active'], ['ended', 'Ended'], ['all', 'All']].map(([k, l]) => (
          <button key={k} className={`pp-chip ${status === k ? 'active' : ''}`} onClick={() => setStatus(k)}>{l}</button>
        ))}
        <span style={{ width: 8 }} />
        {[['', 'All plans'], ['voyager', 'Voyager'], ['globetrotter', 'Globetrotter']].map(([k, l]) => (
          <button key={k || 'all'} className={`pp-chip ${plan === k ? 'active' : ''}`} onClick={() => setPlan(k)}>{l}</button>
        ))}
        <input className="form-input" placeholder="Search name or email" value={search}
          onChange={(e) => setSearch(e.target.value)} style={{ width: 220, marginLeft: 'auto' }} />
      </div>

      {subs.loading && !subs.data ? <div className="pp-empty">Loading…</div> : items.length === 0 ? (
        <div className="pp-empty">No one here yet. People who subscribe in the app, or get a plan from the Test a plan tab, appear here.</div>
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
                    <td><PlanPill plan={r.plan} suffix={r.period === 'yearly' ? 'yearly' : r.period === 'monthly' ? 'monthly' : ''} /></td>
                    <td>
                      <span className={`pp-tag ${tone}`}>{label}</span>
                      {r.environment === 'SANDBOX' && <span className="pp-tag blue" style={{ marginLeft: 6 }}>Test</span>}
                    </td>
                    <td>{r.period_end ? day(r.period_end) : 'No end date'}</td>
                    <td>{r.source === 'admin' ? `Given here by ${r.granted_by || 'admin'}` : r.store === 'app_store' ? 'Bought on App Store' : r.store === 'play_store' ? 'Bought on Google Play' : 'Bought in the app'}</td>
                    <td style={{ textAlign: 'right' }}>
                      {r.source === 'admin' && r.status !== 'expired' && (
                        <button className="btn btn-ghost" style={{ padding: '6px 12px', fontSize: 12 }} onClick={() => backToExplorer(r)}>Back to Explorer</button>
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

/* ── Test a plan ──────────────────────────────────────────────────────── */

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
    if (await setTesters([...testers, e], `${e} added — plan limits now apply to this account`)) {
      setNewEmail('');
      if (!email) setEmail(e);
    }
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
    <div className="pp-section">
      <div className="pp-card">
        <h3>How to test a plan</h3>
        <p className="pp-sub">Try every plan on your own account in the TestFlight / test app — nobody pays, and normal users are not affected.</p>
        <div className="pp-steps">
          <div className="pp-step"><div className="pp-step-num">1</div><div><b>Add your email below</b><span>Plan limits switch on for that account only.</span></div></div>
          <div className="pp-step"><div className="pp-step-num">2</div><div><b>Pick a plan for it</b><span>Explorer, Voyager or Globetrotter — it changes straight away.</span></div></div>
          <div className="pp-step"><div className="pp-step-num">3</div><div><b>Reopen the app</b><span>Profile shows the plan; try Odyssey, Neva, AR and Around You.</span></div></div>
        </div>
      </div>

      <div className="pp-card">
        <h3>1 · Test accounts</h3>
        <p className="pp-sub">These accounts get plan limits now, before they are on for everyone.</p>
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
            onChange={(e) => setNewEmail(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && addTester()} style={{ width: 280 }} />
          <button className="btn btn-primary" onClick={addTester}>Add test account</button>
        </div>
      </div>

      <div className="pp-card">
        <h3>2 · Give a plan</h3>
        <p className="pp-sub">Works for any account. A plan bought in the app is never touched — the better of the two applies.</p>

        <div className="pp-label">Account</div>
        <input className="form-input" list="pp-testers" type="email" placeholder="Email of the account" value={email}
          onChange={(e) => setEmail(e.target.value)} style={{ width: 320 }} />
        <datalist id="pp-testers">{testers.map((t) => <option key={t} value={t} />)}</datalist>

        <div className="pp-label">Plan</div>
        <div className="pp-choice-grid">
          {PLANS.map((p) => (
            <button key={p} className={`pp-choice ${plan === p ? 'active' : ''}`} onClick={() => setPlan(p)}>
              <div className="t"><span className="pp-swatch" style={{ background: PLAN[p].color }} />{PLAN[p].name}</div>
              <div className="d">{p === 'explorer' ? 'Free plan — takes away a hand-given plan' : PLAN[p].price}</div>
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

      <div className="pp-card">
        <h3>Plans given by hand</h3>
        {grants.length === 0 ? <div className="pp-empty">None right now.</div> : (
          <div className="pp-activity">
            {grants.map((g) => (
              <div key={g.user_id} className="pp-activity-item" style={{ alignItems: 'center' }}>
                <div className="pp-avatar">{(g.name || g.email || '?')[0].toUpperCase()}</div>
                <div style={{ flex: 1 }}>
                  <div className="pp-activity-text"><strong>{g.email}</strong> <PlanPill plan={g.plan} /></div>
                  <div className="pp-activity-meta">{g.period_end ? `Ends ${when(g.period_end)}` : 'No end date'}</div>
                </div>
                <button className="btn btn-ghost" style={{ padding: '6px 12px', fontSize: 12 }}
                  onClick={async () => {
                    try {
                      await apiFetch(`/admin/billing/grant/${g.user_id}`, { method: 'DELETE' });
                      notify(`${g.email} is back on Explorer`);
                      given.refetch();
                      onChanged();
                    } catch (e) { notify(e.message, 'error'); }
                  }}>
                  Back to Explorer
                </button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

/* ── Limits ───────────────────────────────────────────────────────────── */

// [key, label, hint, kind]; kind: num | days | km | bands | usd | lite | yesno
const LIMIT_GROUPS = [
  ['Odyssey trip planner', [
    ['odyssey_per_period', 'Plans a month', 'Free plans reset on the 1st; paid on their billing day', 'num'],
    ['odyssey_max_days', 'Longest trip', '', 'days'],
    ['odyssey_lite', 'Ratings & opening hours', '“Hidden” = Lite plan', 'lite'],
    ['priority_queue', 'Priority queue', 'Plans start before others when it is busy', 'yesno'],
  ]],
  ['Neva', [
    ['neva_per_day', 'Messages a day', 'Resets at midnight UTC', 'num'],
  ]],
  ['Map, Around You & AR', [
    ['ar_radius_m', 'AR view range', 'Medical is never limited', 'km'],
    ['nearby_max_radius_m', 'Around You / Discover reach', 'Medical / Hospital always full range', 'km'],
    ['banded_max_bands', 'Around You distance bands', '3 = all bands', 'bands'],
    ['map_day_usd', 'Live map data — per day', '0 = no daily limit', 'usd'],
    ['map_month_usd', 'Live map data — per month', '0 = no monthly limit', 'usd'],
  ]],
];

function LimitsTab({ s, save }) {
  const [form, setForm] = useState(null);
  const [seen, setSeen] = useState(null);
  if (s && s !== seen) {
    setSeen(s);
    setForm(JSON.parse(JSON.stringify(s.plan_limits || DOC_LIMITS)));
  }
  if (!form) return null;

  const set = (p, k, v) => setForm((f) => ({ ...f, [p]: { ...f[p], [k]: v } }));

  const cell = (p, k, kind) => {
    const v = form[p]?.[k];
    if (kind === 'lite' || kind === 'yesno') {
      const yes = kind === 'lite' ? !v : !!v;
      return (
        <button className={`pp-toggle ${yes ? 'yes' : ''}`} onClick={() => set(p, k, kind === 'lite' ? yes : !v)}>
          {kind === 'lite' ? (v ? 'Hidden' : 'Shown') : (v ? 'Yes' : 'No')}
        </button>
      );
    }
    const unit = { days: 'days', km: 'km', bands: 'bands', usd: '$', num: '' }[kind];
    const shown = kind === 'km' ? (v || 0) / 1000 : v;
    return (
      <span className="pp-num">
        {kind === 'usd' && <em>$</em>}
        <input className="form-input" type="number" min="0" step={kind === 'usd' ? '0.01' : kind === 'km' ? '0.5' : '1'}
          value={shown ?? ''} onChange={(e) => {
            const n = e.target.value === '' ? 0 : Number(e.target.value);
            set(p, k, kind === 'km' ? Math.round(n * 1000) : n);
          }} />
        {unit && kind !== 'usd' && <em>{unit}</em>}
      </span>
    );
  };

  return (
    <div className="pp-card">
      <h3>What each plan allows</h3>
      <p className="pp-sub">Change a number and press Save — the app follows within a minute, no app update needed.</p>
      <div className="table-wrap">
        <table className="pp-limits">
          <thead>
            <tr><th style={{ width: '34%' }} />{PLANS.map((p) => <th key={p}><PlanPill plan={p} /></th>)}</tr>
          </thead>
          <tbody>
            {LIMIT_GROUPS.map(([group, rows]) => [
              <tr key={group} className="group"><td colSpan={4}>{group}</td></tr>,
              ...rows.map(([k, label, hint, kind]) => (
                <tr key={k}>
                  <td>{label}{hint && <span className="hint">{hint}</span>}</td>
                  {PLANS.map((p) => <td key={p}>{cell(p, k, kind)}</td>)}
                </tr>
              )),
            ])}
          </tbody>
        </table>
      </div>
      <div className="pp-actions">
        <button className="btn btn-ghost" onClick={() => setForm(JSON.parse(JSON.stringify(DOC_LIMITS)))}>Reset to the packages document</button>
        <button className="btn btn-primary" onClick={() => save({ plan_limits: form }, 'Limits saved')}>Save limits</button>
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

  const checks = [
    ['App Store key (appl_…)', !!s.revenuecat_ios_key],
    ['Google Play key (goog_…)', !!s.revenuecat_android_key],
    ['RevenueCat secret key (sk_…, V1)', !!s.revenuecat_api_key_set],
    ['Webhook password', !!s.revenuecat_webhook_secret_set],
  ];
  const done = checks.filter(([, ok]) => ok).length;

  const submit = async () => {
    const body = { revenuecat_ios_key: ios.trim(), revenuecat_android_key: android.trim(), min_app_version: minVersion.trim() };
    if (secret.trim()) body.revenuecat_api_key = secret.trim();
    if (hook.trim()) body.revenuecat_webhook_secret = hook.trim();
    if (await save(body, 'Store setup saved')) {
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
        <h3>Connection to the stores · {done} of {checks.length} done</h3>
        <p className="pp-sub">Values come from RevenueCat (Project settings → API keys). Purchases work once all four are done.</p>
        {checks.map(([label, ok]) => (
          <div key={label} className="pp-check">
            <div className="lbl"><span className={`pp-tick ${ok ? 'ok' : 'no'}`}>{ok ? '✓' : ''}</span>{label}</div>
            <span className={`pp-tag ${ok ? 'green' : ''}`}>{ok ? 'Connected' : 'Not set'}</span>
          </div>
        ))}
      </div>

      <div className="pp-card">
        <h3>Webhook address for RevenueCat</h3>
        <p className="pp-sub">RevenueCat → Integrations → Webhooks: paste this address, and use the same password as below in “Authorization header”.</p>
        <div className="pp-code">
          {WEBHOOK_URL}
          <button className="btn btn-ghost" style={{ padding: '4px 10px', fontSize: 12 }} onClick={copy}>Copy</button>
        </div>
      </div>

      <div className="pp-card">
        <h3>Keys</h3>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '0 16px' }}>
          <div className="form-group" style={{ marginBottom: 16 }}>
            <label className="form-label">App Store key (appl_…)</label>
            <input className="form-input" value={ios} onChange={(e) => setIos(e.target.value)} placeholder="appl_…" />
          </div>
          <div className="form-group" style={{ marginBottom: 16 }}>
            <label className="form-label">Google Play key (goog_…)</label>
            <input className="form-input" value={android} onChange={(e) => setAndroid(e.target.value)} placeholder="goog_…" />
          </div>
          <SecretField label="RevenueCat secret key (sk_…)" tag={s.revenuecat_api_key_set ? 'SET — leave empty to keep' : 'NOT SET'}
            value={secret} onChange={setSecret} placeholder="sk_…" />
          <SecretField label="Webhook password" tag={s.revenuecat_webhook_secret_set ? 'SET — leave empty to keep' : 'NOT SET'}
            value={hook} onChange={setHook} placeholder="A long random password" />
        </div>

        <div className="form-group" style={{ maxWidth: 340 }}>
          <label className="form-label">Oldest app version allowed</label>
          <input className="form-input" value={minVersion} onChange={(e) => setMinVersion(e.target.value)} placeholder="e.g. 1.0.18 — empty = no minimum" />
          <span className="pp-muted">Older versions are asked to update. Set it on release day.</span>
        </div>

        <div className="pp-actions">
          <button className="btn btn-primary" onClick={submit}>Save store setup</button>
        </div>
      </div>
    </div>
  );
}
