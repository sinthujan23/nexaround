import { useState } from 'react';
import { apiFetch, useApi } from '../api';
import { useToast } from '../hooks';
import { Badge, Card, EmptyState, PageError, PageLoading, SecretField, StatCard, Switch, Toast } from '../components/Kit';
import { CreditCardIcon, DollarIcon, TrendingDownIcon, TrendingUpIcon, UsersIcon } from '../components/Icons';

const PLAN_NAMES = { explorer: 'Explorer', voyager: 'Voyager', globetrotter: 'Globetrotter' };
const PLANS = ['explorer', 'voyager', 'globetrotter'];
const WEBHOOK_URL = 'https://api.nexaround.com/api/v1/billing/revenuecat';

// The limits the TL can tune, in the packages document's words.
const LIMIT_FIELDS = [
  ['odyssey_per_period', 'Odyssey plans per month', 'number'],
  ['odyssey_max_days', 'Longest trip (days)', 'number'],
  ['odyssey_lite', 'Lite plan (ratings and hours hidden)', 'bool'],
  ['neva_per_day', 'Neva messages per day', 'number'],
  ['ar_radius_m', 'AR view range (metres)', 'number'],
  ['nearby_max_radius_m', 'Around You / Discover reach (metres)', 'number'],
  ['banded_max_bands', 'Around You distance bands shown', 'number'],
  ['map_day_usd', 'Live map data: daily limit (USD, 0 = none)', 'money'],
  ['map_month_usd', 'Live map data: monthly limit (USD, 0 = none)', 'money'],
  ['priority_queue', 'Priority Odyssey queue', 'bool'],
];

const usd = (v) => (v == null ? '—' : `$${Number(v).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`);
const day = (v) => (v ? new Date(v).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : '—');
const when = (v) => (v ? new Date(v).toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '—');

const statusTone = (s) => ({ active: 'green', cancelled: 'yellow', billing_issue: 'red', expired: 'ghost' }[s] || 'ghost');
const statusLabel = (s) => ({ active: 'Active', cancelled: 'Cancelled (runs to end)', billing_issue: 'Payment problem', expired: 'Ended' }[s] || s || '—');

/**
 * Subscription plans: who pays, what it brings in, hand-granted plans, and
 * the plan settings (limits on/off, test accounts, limit numbers, RevenueCat).
 * Payments happen in the app through Apple / Google; RevenueCat reports them
 * to the backend, which is what this page reads.
 */
export default function Payments() {
  const [toast, notify] = useToast();
  const [status, setStatus] = useState('active');
  const [plan, setPlan] = useState('');
  const [search, setSearch] = useState('');

  const overview = useApi('/admin/billing/overview');
  const subs = useApi(`/admin/billing/subscriptions?status=${status}${plan ? `&plan=${plan}` : ''}${search ? `&search=${encodeURIComponent(search)}` : ''}`);
  const events = useApi('/admin/billing/events?limit=30');

  if (overview.loading && !overview.data) return <PageLoading />;
  if (overview.error && !overview.data) return <PageError error={overview.error} onRetry={overview.refetch} />;
  const o = overview.data || {};

  const revoke = async (userId) => {
    if (!window.confirm('Remove this hand-granted plan? A store subscription, if any, is not affected.')) return;
    try {
      await apiFetch(`/admin/billing/grant/${userId}`, { method: 'DELETE' });
      notify('Grant removed');
      subs.refetch();
      overview.refetch();
    } catch (e) {
      notify(e.message, 'error');
    }
  };

  return (
    <div>
      <Toast toast={toast} />
      {!o.enforcing && (
        <div className="card" style={{ borderLeft: '4px solid var(--warning, #f5a524)', marginBottom: '16px' }}>
          <strong>Plan limits are off.</strong>{' '}
          Everyone has unlimited use until “Limits on for everyone” is switched on in Plan settings below
          (test accounts listed there get the limits already).
        </div>
      )}

      <div className="stats-grid">
        <StatCard icon={UsersIcon} value={o.subscribers ?? 0} label="Paying subscribers" />
        <StatCard icon={DollarIcon} value={usd(o.mrr_usd)} label="Monthly recurring revenue (est.)" />
        <StatCard icon={TrendingUpIcon} value={usd(o.revenue_month_usd)} label="Charged this month" />
        <StatCard
          icon={TrendingDownIcon}
          iconColor="var(--danger)"
          value={o.cancellations_30d ?? 0}
          label="Cancellations, last 30 days"
          change={`${o.new_30d ?? 0} new · ${o.renewals_30d ?? 0} renewals`}
          trend={null}
        />
      </div>
      <p style={{ color: 'var(--text-secondary)', fontSize: '12.5px', margin: '-6px 0 16px' }}>
        {o.note} Test (sandbox) purchases are left out. {o.admin_grants ?? 0} hand-granted plan(s) active.
      </p>

      <Card title="Subscribers by plan">
        <div className="table-wrap">
          <table>
            <thead><tr><th>Plan</th><th>Monthly</th><th>Yearly</th><th>Total</th></tr></thead>
            <tbody>
              {['voyager', 'globetrotter'].map((p) => {
                const b = (o.by_plan || {})[p] || {};
                return (
                  <tr key={p}>
                    <td>{PLAN_NAMES[p]}</td><td>{b.monthly ?? 0}</td><td>{b.yearly ?? 0}</td><td><strong>{b.total ?? 0}</strong></td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </Card>

      <Card
        title="Subscriptions"
        style={{ marginTop: '16px' }}
        action={(
          <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
            <select className="form-input" value={status} onChange={(e) => setStatus(e.target.value)} style={{ width: 'auto' }}>
              <option value="active">Active</option>
              <option value="ended">Ended</option>
              <option value="all">All</option>
            </select>
            <select className="form-input" value={plan} onChange={(e) => setPlan(e.target.value)} style={{ width: 'auto' }}>
              <option value="">All plans</option>
              <option value="voyager">Voyager</option>
              <option value="globetrotter">Globetrotter</option>
            </select>
            <input className="form-input" placeholder="Search email or name" value={search}
              onChange={(e) => setSearch(e.target.value)} style={{ width: '200px' }} />
          </div>
        )}
      >
        {subs.loading && !subs.data ? <p>Loading…</p> : (subs.data?.items || []).length === 0 ? (
          <EmptyState icon={<CreditCardIcon size={28} />} title="No subscriptions here yet">
            Purchases made in the app appear here within seconds.
          </EmptyState>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr><th>Explorer</th><th>Plan</th><th>Billing</th><th>Status</th><th>Until</th><th>Source</th><th /></tr>
              </thead>
              <tbody>
                {subs.data.items.map((s) => (
                  <tr key={`${s.user_id}-${s.source}`}>
                    <td>
                      <div style={{ fontWeight: 600 }}>{s.name || '—'}</div>
                      <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>{s.email}</div>
                    </td>
                    <td>{PLAN_NAMES[s.plan] || s.plan}</td>
                    <td>{s.period ? (s.period === 'yearly' ? 'Yearly' : 'Monthly') : '—'}</td>
                    <td>
                      <Badge tone={statusTone(s.status)}>{statusLabel(s.status)}</Badge>
                      {s.environment === 'SANDBOX' && <Badge tone="blue" style={{ marginLeft: 4 }}>Test</Badge>}
                    </td>
                    <td>{s.period_end ? day(s.period_end) : 'No end'}</td>
                    <td>
                      {s.source === 'admin'
                        ? <span title={s.note || ''}>Granted by {s.granted_by || 'admin'}</span>
                        : (s.store === 'app_store' ? 'App Store' : s.store === 'play_store' ? 'Google Play' : (s.store || 'Store'))}
                    </td>
                    <td>
                      {s.source === 'admin' && (
                        <button className="btn btn-ghost" style={{ padding: '4px 10px', fontSize: '12px' }} onClick={() => revoke(s.user_id)}>
                          Remove
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            <p style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>{subs.data.total} in total</p>
          </div>
        )}
      </Card>

      <GrantForm notify={notify} onDone={() => { subs.refetch(); overview.refetch(); }} />

      <Card title="Latest store events" style={{ marginTop: '16px' }}>
        {(events.data || []).length === 0 ? (
          <p style={{ color: 'var(--text-secondary)', fontSize: '13px' }}>
            Nothing yet. RevenueCat sends an event for every purchase, renewal, cancellation and expiry.
          </p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead><tr><th>When</th><th>Event</th><th>Explorer</th><th>Product</th><th>Charged</th></tr></thead>
              <tbody>
                {events.data.map((e) => (
                  <tr key={e.event_id}>
                    <td>{when(e.event_at)}</td>
                    <td>
                      {e.type.replaceAll('_', ' ').toLowerCase()}
                      {e.environment === 'SANDBOX' && <Badge tone="blue" style={{ marginLeft: 4 }}>Test</Badge>}
                    </td>
                    <td>{e.email || '—'}</td>
                    <td>{e.product_id || '—'}</td>
                    <td>
                      {e.price_usd != null ? usd(e.price_usd) : '—'}
                      {e.currency && e.currency !== 'USD' && e.price_local != null && (
                        <span style={{ color: 'var(--text-secondary)', fontSize: '12px' }}> ({e.currency} {e.price_local})</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <PlanSettings notify={notify} onSaved={overview.refetch} />
    </div>
  );
}

function GrantForm({ notify, onDone }) {
  const [email, setEmail] = useState('');
  const [plan, setPlan] = useState('voyager');
  const [days, setDays] = useState('30');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async (ev) => {
    ev.preventDefault();
    setBusy(true);
    try {
      await apiFetch('/admin/billing/grant', {
        method: 'POST',
        body: JSON.stringify({ email: email.trim(), plan, days: days ? Number(days) : null, note: note.trim() || null }),
      });
      notify(`${PLAN_NAMES[plan]} granted to ${email.trim()}`);
      setEmail('');
      setNote('');
      onDone();
    } catch (e) {
      notify(e.message, 'error');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card title="Give a plan by hand" style={{ marginTop: '16px' }}>
      <p style={{ color: 'var(--text-secondary)', fontSize: '13px', marginTop: 0 }}>
        For testers, support and goodwill. It never touches a store subscription; the better of the two applies.
      </p>
      <form onSubmit={submit} style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', alignItems: 'center' }}>
        <input className="form-input" type="email" required placeholder="Explorer's email" value={email}
          onChange={(e) => setEmail(e.target.value)} style={{ width: '240px' }} />
        <select className="form-input" value={plan} onChange={(e) => setPlan(e.target.value)} style={{ width: 'auto' }}>
          <option value="voyager">Voyager</option>
          <option value="globetrotter">Globetrotter</option>
        </select>
        <input className="form-input" type="number" min="1" max="3650" placeholder="Days (empty = no end)" value={days}
          onChange={(e) => setDays(e.target.value)} style={{ width: '170px' }} />
        <input className="form-input" placeholder="Note (optional)" value={note}
          onChange={(e) => setNote(e.target.value)} style={{ width: '200px' }} />
        <button className="btn btn-primary" type="submit" disabled={busy}>{busy ? 'Saving…' : 'Grant plan'}</button>
      </form>
    </Card>
  );
}

function PlanSettings({ notify, onSaved }) {
  const { data, loading, refetch } = useApi('/admin/billing/settings');
  const [form, setForm] = useState(null);
  const [secrets, setSecrets] = useState({ revenuecat_api_key: '', revenuecat_webhook_secret: '' });
  const [busy, setBusy] = useState(false);

  // A fresh copy to edit whenever the server's settings arrive or change.
  const [seen, setSeen] = useState(null);
  if (data && data !== seen) {
    setSeen(data);
    setForm(JSON.parse(JSON.stringify(data)));
  }

  if (loading || !form) return null;

  const setLimit = (p, key, value) => setForm((f) => ({
    ...f, plan_limits: { ...f.plan_limits, [p]: { ...f.plan_limits[p], [key]: value } },
  }));

  const save = async () => {
    if (form.plans_enforce && !data.plans_enforce
      && !window.confirm('Switch plan limits on for EVERYONE now? Free users will be limited immediately.')) return;
    setBusy(true);
    try {
      const body = {
        plans_enforce: form.plans_enforce,
        plans_enforce_users: form.plans_enforce_users,
        min_app_version: form.min_app_version,
        plan_limits: form.plan_limits,
        revenuecat_ios_key: form.revenuecat_ios_key,
        revenuecat_android_key: form.revenuecat_android_key,
      };
      if (secrets.revenuecat_api_key.trim()) body.revenuecat_api_key = secrets.revenuecat_api_key.trim();
      if (secrets.revenuecat_webhook_secret.trim()) body.revenuecat_webhook_secret = secrets.revenuecat_webhook_secret.trim();
      await apiFetch('/admin/billing/settings', { method: 'PUT', body: JSON.stringify(body) });
      setSecrets({ revenuecat_api_key: '', revenuecat_webhook_secret: '' });
      notify('Plan settings saved');
      refetch();
      onSaved();
    } catch (e) {
      notify(e.message, 'error');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card
      title="Plan settings"
      style={{ marginTop: '16px' }}
      action={<button className="btn btn-primary" onClick={save} disabled={busy}>{busy ? 'Saving…' : 'Save settings'}</button>}
    >
      <div style={{ display: 'grid', gap: '14px', maxWidth: '760px' }}>
        <Switch
          checked={!!form.plans_enforce}
          onChange={(v) => setForm({ ...form, plans_enforce: v })}
          label={<span style={{ marginLeft: 8 }}><strong>Limits on for everyone</strong> — switch on the day the app with the plans screen is released</span>}
        />
        <div className="form-group">
          <label className="form-label">Test accounts with limits already on (emails, comma-separated)</label>
          <input className="form-input" value={form.plans_enforce_users || ''}
            onChange={(e) => setForm({ ...form, plans_enforce_users: e.target.value })} placeholder="tester@example.com, …" />
        </div>
        <div className="form-group">
          <label className="form-label">Oldest app version allowed (older versions are asked to update; empty = none)</label>
          <input className="form-input" value={form.min_app_version || ''} style={{ width: '160px' }}
            onChange={(e) => setForm({ ...form, min_app_version: e.target.value })} placeholder="1.0.18" />
        </div>
      </div>

      <h4 style={{ margin: '20px 0 8px' }}>Limits per plan</h4>
      <div className="table-wrap">
        <table>
          <thead><tr><th>Limit</th>{PLANS.map((p) => <th key={p}>{PLAN_NAMES[p]}</th>)}</tr></thead>
          <tbody>
            {LIMIT_FIELDS.map(([key, label, type]) => (
              <tr key={key}>
                <td>{label}</td>
                {PLANS.map((p) => {
                  const v = form.plan_limits?.[p]?.[key];
                  return (
                    <td key={p}>
                      {type === 'bool' ? (
                        <input type="checkbox" checked={!!v} onChange={(e) => setLimit(p, key, e.target.checked)} />
                      ) : (
                        <input className="form-input" type="number" step={type === 'money' ? '0.01' : '1'} min="0"
                          value={v ?? ''} style={{ width: '110px' }}
                          onChange={(e) => setLimit(p, key, e.target.value === '' ? 0 : Number(e.target.value))} />
                      )}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h4 style={{ margin: '20px 0 8px' }}>RevenueCat</h4>
      <p style={{ color: 'var(--text-secondary)', fontSize: '13px', marginTop: 0 }}>
        Webhook URL: <code>{WEBHOOK_URL}</code> — set its Authorization header value in RevenueCat to the webhook secret below.
      </p>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '0 16px', maxWidth: '760px' }}>
        <div className="form-group" style={{ marginBottom: '16px' }}>
          <label className="form-label">App Store public SDK key (appl_…)</label>
          <input className="form-input" value={form.revenuecat_ios_key || ''}
            onChange={(e) => setForm({ ...form, revenuecat_ios_key: e.target.value })} />
        </div>
        <div className="form-group" style={{ marginBottom: '16px' }}>
          <label className="form-label">Google Play public SDK key (goog_…)</label>
          <input className="form-input" value={form.revenuecat_android_key || ''}
            onChange={(e) => setForm({ ...form, revenuecat_android_key: e.target.value })} />
        </div>
        <SecretField
          label="Secret API key (sk_…)"
          tag={data.revenuecat_api_key_set ? 'SET — leave empty to keep' : 'NOT SET'}
          value={secrets.revenuecat_api_key}
          onChange={(v) => setSecrets({ ...secrets, revenuecat_api_key: v })}
          placeholder="sk_…"
        />
        <SecretField
          label="Webhook secret"
          tag={data.revenuecat_webhook_secret_set ? 'SET — leave empty to keep' : 'NOT SET'}
          value={secrets.revenuecat_webhook_secret}
          onChange={(v) => setSecrets({ ...secrets, revenuecat_webhook_secret: v })}
          placeholder="A long random string"
        />
      </div>
    </Card>
  );
}
