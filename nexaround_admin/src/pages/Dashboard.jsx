import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useApi } from '../api';
import { AlertTriangleIcon, InboxIcon, MapPinIcon, RefreshIcon } from '../components/Icons';
import { Card, Badge, Modal, Loading, EmptyState, PageLoading, PageError } from '../components/Kit';

const USAGE_DAYS = 7;

// Display names and chart colours for the `provider` keys in api_events.
// A provider missing here still shows, with its key as the name.
const PROVIDERS = {
  google_maps: { label: 'Google Maps', color: '#4285F4' },
  geoapify: { label: 'Geoapify', color: '#00897b' },
  gemini: { label: 'Gemini', color: '#8e24aa' },
  mapbox: { label: 'Mapbox', color: '#4264fb' },
  serpapi: { label: 'SerpAPI', color: '#e8710a' },
  wegotrip: { label: 'WeGoTrip', color: '#d81b60' },
  airalo: { label: 'Airalo', color: '#0097a7' },
  gettransfer: { label: 'GetTransfer', color: '#5e35b1' },
  atlas: { label: 'HelloSafe Atlas', color: '#2e7d32' },
  unsplash: { label: 'Unsplash', color: '#455a64' },
  app_stores: { label: 'App Stores', color: '#6d4c41' },
};

function providerMeta(key) {
  return PROVIDERS[key] || {
    label: key.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()),
    color: '#64748b',
  };
}

/** 'YYYY-MM-DD' (a Sri Lanka date from the API) → 'Mo'. */
function dayLabel(isoDate) {
  const [y, m, d] = isoDate.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d))
    .toLocaleDateString('en-US', { weekday: 'short', timeZone: 'UTC' })
    .slice(0, 2);
}

/** 'YYYY-MM' → 'May' (with the year when it isn't this year's). */
function monthLabel(yearMonth) {
  const [y, m] = yearMonth.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, 1));
  const sameYear = y === new Date().getFullYear();
  return date.toLocaleDateString('en-US', { month: 'short', ...(sameYear ? {} : { year: '2-digit' }), timeZone: 'UTC' });
}

function changeText(calls, prevCalls) {
  if (!prevCalls) return calls ? `New in the last ${USAGE_DAYS} days` : `None in the last ${USAGE_DAYS * 2} days`;
  const pct = Math.round(((calls - prevCalls) / prevCalls) * 100);
  return `${pct > 0 ? '+' : ''}${pct}% vs previous ${USAGE_DAYS} days`;
}

function formatTime(isoStr) {
  if (!isoStr) return '';
  try {
    const date = new Date(isoStr);
    const now = new Date();
    const diffMs = now - date;
    const diffMins = Math.floor(diffMs / 60000);
    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins}m ago`;
    const diffHours = Math.floor(diffMins / 60);
    if (diffHours < 24) return `${diffHours}h ago`;
    return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Colombo' });
  } catch {
    return isoStr;
  }
}

/** One provider's calls per operation, from the data the card already has. */
function BreakdownModal({ provider, onClose }) {
  const { label, color } = providerMeta(provider.provider);
  const cached = provider.requests - provider.calls;

  return (
    <Modal title={`${label}: last ${USAGE_DAYS} days`} onClose={onClose} maxWidth="520px">
      <div style={{
        background: 'var(--bg-dark)', borderRadius: '12px', padding: '12px 16px',
        display: 'flex', justifyContent: 'space-between', alignItems: 'center',
        marginBottom: '16px', border: `1px solid ${color}33`,
      }}>
        <div>
          <div style={{ fontSize: '13px', color: 'var(--text-secondary)', fontWeight: 600 }}>Calls to {label}</div>
          {cached > 0 && (
            <div style={{ fontSize: '11px', color: 'var(--text-secondary)', marginTop: '2px' }}>
              + {cached.toLocaleString()} answered from our cache
            </div>
          )}
        </div>
        <span style={{ fontSize: '22px', fontWeight: 800, color, letterSpacing: '-0.5px' }}>
          {provider.calls.toLocaleString()}
        </span>
      </div>

      {provider.operations.length === 0 ? (
        <EmptyState>No requests in the last {USAGE_DAYS} days.</EmptyState>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
          {provider.operations.map((op) => {
            const pct = provider.calls > 0 ? Math.round((op.calls / provider.calls) * 100) : 0;
            return (
              <div key={op.operation} style={{
                background: 'var(--bg-dark)', borderRadius: '10px',
                padding: '12px 14px', border: '1px solid var(--border)',
              }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '6px' }}>
                  <span style={{
                    fontSize: '12px', color: 'var(--text-primary)', fontFamily: 'monospace',
                    fontWeight: 600, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                  }} title={op.operation}>
                    {op.operation}
                  </span>
                  <span style={{ fontSize: '13px', fontWeight: 800, color, marginLeft: '8px', flexShrink: 0 }}>
                    {op.calls.toLocaleString()} <span style={{ color: 'var(--text-secondary)', fontWeight: 500, fontSize: '11px' }}>calls</span>
                  </span>
                </div>
                <div style={{ height: '4px', background: 'var(--bg-card)', borderRadius: '4px', overflow: 'hidden' }}>
                  <div style={{ height: '100%', width: `${pct}%`, background: color, borderRadius: '4px' }} />
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '10px', color: 'var(--text-secondary)', marginTop: '3px' }}>
                  <span>{op.requests > op.calls ? `${op.requests.toLocaleString()} requests in all` : ''}</span>
                  <span>{pct}%</span>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </Modal>
  );
}

function ProviderTile({ provider, days, onOpen }) {
  const { label, color } = providerMeta(provider.provider);
  const values = provider.daily_calls;
  const maxVal = Math.max(...values, 1);
  const lastIdx = values.length - 1;
  const x = (i) => `${lastIdx > 0 ? (i / lastIdx) * 100 : 50}%`;
  const y = (v) => `${100 - (v / maxVal) * 90}%`;
  const cachedPct = provider.requests > 0
    ? Math.round(((provider.requests - provider.calls) / provider.requests) * 100) : 0;

  return (
    <button
      type="button"
      onClick={onOpen}
      title={`${label}: calls per operation`}
      style={{
        background: 'var(--bg-dark)', padding: '16px', borderRadius: '12px',
        border: '1px solid var(--border)', cursor: 'pointer', textAlign: 'left',
        font: 'inherit', color: 'inherit', transition: 'all 0.2s',
      }}
      onMouseEnter={(e) => {
        e.currentTarget.style.border = `1px solid ${color}66`;
        e.currentTarget.style.boxShadow = `0 4px 20px ${color}22`;
        e.currentTarget.style.transform = 'translateY(-2px)';
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.border = '1px solid var(--border)';
        e.currentTarget.style.boxShadow = 'none';
        e.currentTarget.style.transform = 'none';
      }}
    >
      <div style={{ display: 'flex', justifyContent: 'space-between', gap: '8px' }}>
        <span style={{ fontWeight: 700, fontSize: '13px', color: 'var(--text-primary)' }}>{label}</span>
        <span style={{ fontSize: '12px', color, fontWeight: 700, whiteSpace: 'nowrap' }}>
          {provider.calls.toLocaleString()} calls
        </span>
      </div>
      <div style={{ fontSize: '11px', color: 'var(--text-secondary)', marginTop: '4px', minHeight: '15px' }}>
        {changeText(provider.calls, provider.prev_calls)}
        {cachedPct > 0 && ` · ${cachedPct}% from cache`}
      </div>
      <div style={{ position: 'relative', height: '60px', margin: '14px 0 10px' }}>
        <svg style={{ width: '100%', height: '100%', overflow: 'visible' }}>
          {values.slice(0, -1).map((v, i) => (
            <line key={i} x1={x(i)} y1={y(v)} x2={x(i + 1)} y2={y(values[i + 1])}
              stroke={color} strokeWidth="2" strokeLinecap="round" />
          ))}
          {values.map((v, i) => (
            <circle key={i} cx={x(i)} cy={y(v)} r="4" fill="var(--bg-dark)" stroke={color} strokeWidth="2">
              <title>{`${days[i]}: ${v.toLocaleString()} calls`}</title>
            </circle>
          ))}
        </svg>
      </div>
      <div style={{ display: 'flex', justifyContent: 'space-between', padding: '0 2px' }}>
        {days.map((d, i) => (
          <span key={d} style={{ fontSize: '9px', fontWeight: i === lastIdx ? 700 : 400, color: i === lastIdx ? 'var(--text-primary)' : 'var(--text-secondary)' }}>
            {dayLabel(d)}
          </span>
        ))}
      </div>
    </button>
  );
}

/**
 * Third-party API calls from the live telemetry. `usage` is the page's
 * useApi result for /dashboard/api-usage, which the tiles above share; this
 * card's Refresh reloads only that, keeping the current figures on screen.
 */
function ApiUsageCard({ usage }) {
  const { data, loading, error, refetch } = usage;
  const [selected, setSelected] = useState(null);

  const providers = (data?.providers || []).filter((p) => p.requests > 0);
  const updatedAt = data && new Date(data.generated_at).toLocaleTimeString(undefined, {
    hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Colombo',
  });

  return (
    <Card style={{ marginBottom: '24px' }}>
      {selected && <BreakdownModal provider={selected} onClose={() => setSelected(null)} />}

      <div className="card-header" style={{ marginBottom: '16px', paddingBottom: '12px', borderBottom: '1px solid var(--border)' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '2px' }}>
          <div className="card-title">API Usage &amp; Monitoring</div>
          <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
            Calls that reached each provider, last {USAGE_DAYS} days (Sri Lanka time). Click a provider for its breakdown.
          </div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          {updatedAt && <Badge tone="ghost">Updated {updatedAt}</Badge>}
          <button
            id="dashboard-refresh-btn"
            type="button"
            onClick={refetch}
            disabled={loading}
            title="Refresh API usage"
            style={{
              background: 'var(--bg-dark)', border: '1px solid var(--border)',
              borderRadius: '50px', padding: '7px 16px', cursor: loading ? 'default' : 'pointer',
              color: 'var(--text-primary)', fontSize: '12px', fontWeight: 700,
              display: 'flex', alignItems: 'center', gap: '7px', letterSpacing: '0.2px',
            }}
          >
            <svg
              width="14" height="14" viewBox="0 0 24 24" fill="none"
              stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"
              style={{ animation: loading ? 'spin 1s linear infinite' : 'none' }}
            >
              <polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 .49-3.61"/>
            </svg>
            {loading ? 'Refreshing…' : 'Refresh'}
          </button>
        </div>
      </div>

      {!data && loading && <Loading>Loading API usage…</Loading>}
      {!data && !loading && error && <EmptyState>Could not load API usage: {error}</EmptyState>}
      {data && (
        <>
          {error && (
            <div style={{ color: 'var(--error)', fontSize: '12px', marginBottom: '12px' }}>
              Refresh failed: {error}. Showing the figures from {updatedAt}.
            </div>
          )}
          {providers.length === 0 ? (
            <EmptyState>No third-party API requests in the last {USAGE_DAYS} days.</EmptyState>
          ) : (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(240px, 1fr))', gap: '16px' }}>
              {providers.map((p) => (
                <ProviderTile key={p.provider} provider={p} days={data.days} onOpen={() => setSelected(p)} />
              ))}
            </div>
          )}
        </>
      )}
    </Card>
  );
}

function plural(n, one, many) {
  return `${n.toLocaleString()} ${n === 1 ? one : many}`;
}

/** Totals across providers, for the API tiles above the API card. */
function usageTotals({ days, providers }) {
  const sum = (key) => providers.reduce((n, p) => n + p[key], 0);
  const topCost = providers.reduce((top, p) => (p.est_cost_usd > (top?.est_cost_usd || 0) ? p : top), null);
  return {
    calls: sum('calls'),
    requests: sum('requests'),
    prevCalls: sum('prev_calls'),
    cost: sum('est_cost_usd'),
    daily: days.map((_, i) => providers.reduce((n, p) => n + p.daily_calls[i], 0)),
    topCost,
  };
}

function greeting() {
  const hour = Number(new Intl.DateTimeFormat('en-GB', { hour: 'numeric', hourCycle: 'h23', timeZone: 'Asia/Colombo' }).format(new Date()));
  if (hour < 12) return 'Good morning';
  return hour < 17 ? 'Good afternoon' : 'Good evening';
}

function Sparkline({ values, label }) {
  const max = Math.max(...values, 1);
  const last = values.length - 1;
  const points = values
    .map((v, i) => `${last > 0 ? (i / last) * 200 : 100},${46 - (v / max) * 42}`)
    .join(' ');
  return (
    <svg width="100%" height="50" viewBox="0 0 200 50" preserveAspectRatio="none" role="img" aria-label={label}>
      <polyline points={points} fill="none" stroke="#2a62b8" strokeWidth="2.5"
        strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
    </svg>
  );
}

function CacheRing({ pct }) {
  const circumference = 2 * Math.PI * 46;
  return (
    <svg width="104" height="104" viewBox="0 0 120 120" role="img" aria-label={`${pct}% of requests answered from cache`} style={{ flexShrink: 0 }}>
      <circle cx="60" cy="60" r="46" fill="none" stroke="#e3e8ea" strokeWidth="14" />
      <circle cx="60" cy="60" r="46" fill="none" stroke="var(--accent)" strokeWidth="14" strokeLinecap="round"
        strokeDasharray={`${(pct / 100) * circumference} ${circumference}`} transform="rotate(-90 60 60)" />
      <text x="60" y="67" textAnchor="middle" fontSize="24" fontWeight="800" fill="var(--text-primary)">{pct}%</text>
    </svg>
  );
}

/** New explorers per month. The last bar is the month so far, so it is lighter. */
function ExplorerBars({ months }) {
  const max = Math.max(...months.map((m) => m.signups), 1);
  const peak = months.findIndex((m) => m.signups === max);
  const current = months.length - 1;
  return (
    <figure style={{ margin: 0 }}>
      <figcaption className="bento-sub" style={{ fontWeight: 600, marginBottom: '8px' }}>New explorers per month</figcaption>
      <div style={{ display: 'flex', alignItems: 'flex-end', gap: '14px', height: '140px' }}>
        {months.map((m, i) => (
          <div
            key={m.month}
            title={`${monthLabel(m.month)}${i === current ? ' so far' : ''}: ${plural(m.signups, 'signup', 'signups')}`}
            style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'flex-end', gap: '6px', height: '100%' }}
          >
            {(i === peak || i === current) && <span style={{ fontSize: '12px', fontWeight: 700 }}>{m.signups.toLocaleString()}</span>}
            <div style={{
              width: '100%', borderRadius: '8px', background: 'var(--accent)', opacity: i === current ? 0.55 : 1,
              height: `${m.signups ? Math.max(4, Math.round((m.signups / max) * 86)) : 0}px`,
            }} />
            <span style={{ fontSize: '12px', color: i === current ? 'var(--text-primary)' : '#2f5d58', fontWeight: i === current ? 700 : 400 }}>
              {monthLabel(m.month)}
            </span>
          </div>
        ))}
      </div>
    </figure>
  );
}

function AttentionStrip({ critical, open, enquiries, pending }) {
  return (
    <section className="attention-strip" aria-labelledby="attention-title">
      <h2 id="attention-title">Needs attention</h2>
      <Link to="/api-usage" className={`attention-item${critical > 0 ? ' critical' : ''}`}>
        <AlertTriangleIcon size={20} />
        <div>
          <strong>{critical > 0 ? plural(critical, 'critical API alert', 'critical API alerts') : 'No critical API alerts'}</strong>
          <span>{open.toLocaleString()} open in all</span>
        </div>
      </Link>
      <Link to="/enquiries" className={`attention-item${enquiries > 0 ? ' warning' : ''}`}>
        <InboxIcon size={20} />
        <div>
          <strong>{enquiries > 0 ? plural(enquiries, 'new enquiry', 'new enquiries') : 'No new enquiries'}</strong>
          <span>{enquiries > 0 ? 'Waiting for a reply' : 'All answered'}</span>
        </div>
      </Link>
      <Link to="/places/review" className="attention-item">
        <MapPinIcon size={20} />
        <div>
          <strong>{pending > 0 ? plural(pending, 'place to review', 'places to review') : 'No places to review'}</strong>
          <span>Review queue</span>
        </div>
      </Link>
    </section>
  );
}

export default function Dashboard() {
  const dash = useApi('/admin/dashboard');
  const usage = useApi(`/admin/dashboard/api-usage?days=${USAGE_DAYS}`);

  if (!dash.data) {
    return dash.loading
      ? <PageLoading />
      : <PageError error={dash.error} onRetry={dash.refetch} title="Dashboard Unavailable">Failed to fetch dashboard metrics: {dash.error}</PageError>;
  }

  const {
    explorers_count,
    new_explorers_7d,
    attractions_count,
    new_attractions_7d,
    pending_approvals_count,
    open_api_alerts,
    critical_api_alerts,
    new_enquiries,
    explorer_growth,
    recent_activity,
  } = dash.data;

  // Start the chart at the first month anyone signed up.
  const firstSignup = explorer_growth.findIndex((m) => m.signups > 0);
  const growth = firstSignup === -1 ? [] : explorer_growth.slice(firstSignup);

  const totals = usage.data && usageTotals(usage.data);
  const callChange = totals?.prevCalls ? Math.round(((totals.calls - totals.prevCalls) / totals.prevCalls) * 100) : null;
  const cachedPct = totals?.requests ? Math.round(((totals.requests - totals.calls) / totals.requests) * 100) : 0;
  const usageNote = !totals && (usage.loading ? 'Loading…' : `Couldn't load: ${usage.error}`);

  const refreshing = dash.loading || usage.loading;
  const refreshAll = () => { dash.refetch(); usage.refetch(); };
  const today = new Intl.DateTimeFormat('en-GB', {
    weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Asia/Colombo',
  }).format(new Date());
  const updatedAt = usage.data && new Date(usage.data.generated_at).toLocaleTimeString('en-US', {
    hour: 'numeric', minute: '2-digit', timeZone: 'Asia/Colombo',
  });

  return (
    <div className="approvals-modern-container">
      <header className="dash-head">
        <div>
          <h1>{greeting()}, Admin</h1>
          <p>{today} · {updatedAt ? `updated ${updatedAt} ` : ''}Sri Lanka time</p>
          {dash.error && <p style={{ color: 'var(--error)' }}>Refresh failed: {dash.error}</p>}
        </div>
        <button type="button" className="dash-refresh" onClick={refreshAll} disabled={refreshing}>
          <RefreshIcon size={14} style={{ animation: refreshing ? 'spin 1s linear infinite' : 'none' }} />
          {refreshing ? 'Refreshing…' : 'Refresh'}
        </button>
      </header>

      <div className="bento">
        <section className="bento-tile big tint-mint" aria-labelledby="tile-explorers">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '12px' }}>
            <div style={{ display: 'flex', flexDirection: 'column' }}>
              <h2 id="tile-explorers">Explorers</h2>
              <span className="bento-value">{explorers_count.toLocaleString()}</span>
            </div>
            <span className="bento-pill">
              {new_explorers_7d > 0 ? `+${new_explorers_7d.toLocaleString()} this week` : 'None new this week'}
            </span>
          </div>
          {growth.length > 0
            ? <ExplorerBars months={growth} />
            : <span className="bento-sub">No signups in the last 12 months.</span>}
        </section>

        <section className="bento-tile tint-sky" aria-labelledby="tile-calls">
          <h2 id="tile-calls">API calls · {USAGE_DAYS} days</h2>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: '10px', flexWrap: 'wrap' }}>
            <span className="bento-value">{totals ? totals.calls.toLocaleString() : '—'}</span>
            {callChange != null && (
              <span style={{ fontSize: '13px', fontWeight: 700 }} title={`vs the ${USAGE_DAYS} days before`}>
                {callChange > 0 ? '+' : ''}{callChange}%
              </span>
            )}
          </div>
          {totals
            ? <Sparkline values={totals.daily} label={`Calls per day: ${totals.daily.map((v) => v.toLocaleString()).join(', ')}`} />
            : <span className="bento-sub">{usageNote}</span>}
        </section>

        <section className="bento-tile plain" aria-labelledby="tile-cache">
          {totals && <CacheRing pct={cachedPct} />}
          <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
            <h2 id="tile-cache">Answered from cache</h2>
            <span className="bento-sub">
              {totals
                ? `${(totals.requests - totals.calls).toLocaleString()} of ${plural(totals.requests, 'request', 'requests')} never reached a provider`
                : usageNote}
            </span>
          </div>
        </section>

        <section className="bento-tile tint-lavender" aria-labelledby="tile-attractions">
          <h2 id="tile-attractions">Live places</h2>
          <span className="bento-value">{attractions_count.toLocaleString()}</span>
          <span className="bento-sub">
            {new_attractions_7d > 0 ? `+${new_attractions_7d.toLocaleString()} this week` : 'None new this week'}
          </span>
        </section>

        <section className="bento-tile tint-sand" aria-labelledby="tile-cost">
          <h2 id="tile-cost">Est. API cost · {USAGE_DAYS} days</h2>
          <span className="bento-value">{totals ? `$${totals.cost.toFixed(2)}` : '—'}</span>
          <span className="bento-sub">
            {totals
              ? `Before free tiers${totals.topCost ? ` · ${providerMeta(totals.topCost.provider).label} $${totals.topCost.est_cost_usd.toFixed(2)}` : ''}`
              : usageNote}
          </span>
        </section>
      </div>

      <AttentionStrip
        critical={critical_api_alerts}
        open={open_api_alerts}
        enquiries={new_enquiries}
        pending={pending_approvals_count}
      />

      <ApiUsageCard usage={usage} />

      <Card title="Recent Activity">
        {recent_activity.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '30px', color: 'var(--text-secondary)', fontSize: '13px' }}>
            No recent activity found.
          </div>
        ) : (
          recent_activity.map((a, i) => (
            <div className="activity-item" key={i}>
              <div className="activity-dot" style={{ background: a.color }} />
              <div>
                <div className="activity-text" style={{ color: 'var(--text-primary)' }}>{a.text}</div>
                <div className="activity-time">{formatTime(a.time)}</div>
              </div>
            </div>
          ))
        )}
      </Card>
    </div>
  );
}
