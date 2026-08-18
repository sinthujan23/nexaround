import { useState, useEffect, useCallback } from 'react';
import { apiGet, apiPost, API_BASE } from '../api';
import {
  CompassIcon, DollarIcon, TrendingUpIcon, TrendingDownIcon,
  RefreshIcon, ClockIcon, SearchIcon,
} from '../components/Icons';

/**
 * API Usage — where every third-party call went, and what it cost.
 *
 * The organising idea is `served_from`: a request answered by Redis, PostGIS or
 * the photo disk cache costs nothing, and one that reached a provider does. The
 * ratio between them is the number that matters, so it leads the page.
 *
 * All costs here are estimates derived from the editable SKU rate table. They
 * are for spotting which operation is expensive and which cache is failing —
 * use the CSV export to reconcile against a real invoice.
 */

const RANGES = [
  { key: '24h', label: 'Last 24 hours', hours: 24 },
  { key: '7d', label: 'Last 7 days', hours: 24 * 7 },
  { key: '30d', label: 'Last 30 days', hours: 24 * 30 },
  { key: '90d', label: 'Last 90 days', hours: 24 * 90 },
];

// Cached tiers read as positive, upstream as spend. Keeping the hues stable
// across every panel is what lets you scan the page rather than read it.
const SOURCE_COLOR = {
  redis: '#007a7c',
  database: '#2a9d8f',
  disk: '#57b8a9',
  memory: '#7fcbbf',
  negative: '#a0a6b5',
  upstream: '#e53935',
};
const SOURCE_LABEL = {
  redis: 'Redis cache', database: 'Local database', disk: 'Photo disk cache',
  memory: 'In-process cache', negative: 'Known-empty cache', upstream: 'Paid provider call',
};

const usd = (n) => `$${Number(n || 0).toFixed(2)}`;
const num = (n) => Number(n || 0).toLocaleString();

function pctDelta(now, prev) {
  if (!prev) return null;
  return ((now - prev) / prev) * 100;
}

/** Small inline sparkline. No chart library — these are a dozen lines of SVG
 *  and adding a dependency for them would be the more expensive choice. */
function StackedBars({ points, height = 180 }) {
  if (!points || points.length === 0) {
    return <div className="empty-state" style={{ padding: '32px 0' }}>No activity in this window.</div>;
  }
  const buckets = [...new Set(points.map((p) => p.t))].sort();
  const keys = [...new Set(points.map((p) => p.key))];
  const byBucket = {};
  buckets.forEach((b) => { byBucket[b] = {}; });
  points.forEach((p) => { byBucket[p.t][p.key] = (byBucket[p.t][p.key] || 0) + p.calls; });
  const totals = buckets.map((b) => keys.reduce((s, k) => s + (byBucket[b][k] || 0), 0));
  const max = Math.max(...totals, 1);

  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'flex-end', gap: '2px', height }}>
        {buckets.map((b, i) => (
          <div
            key={b}
            title={`${new Date(b).toLocaleString()} — ${num(totals[i])} requests`}
            style={{ flex: 1, display: 'flex', flexDirection: 'column-reverse', height: '100%', justifyContent: 'flex-start' }}
          >
            {keys.map((k) => {
              const v = byBucket[b][k] || 0;
              if (!v) return null;
              return (
                <div
                  key={k}
                  style={{
                    height: `${(v / max) * 100}%`,
                    background: SOURCE_COLOR[k] || '#c9d4dd',
                    minHeight: '1px',
                  }}
                />
              );
            })}
          </div>
        ))}
      </div>
      <div style={{ display: 'flex', gap: '16px', flexWrap: 'wrap', marginTop: '14px' }}>
        {keys.map((k) => (
          <span key={k} style={{ display: 'inline-flex', alignItems: 'center', gap: '6px', fontSize: '12px', color: 'var(--text-secondary)' }}>
            <i style={{ width: '10px', height: '10px', borderRadius: '3px', background: SOURCE_COLOR[k] || '#c9d4dd' }} />
            {SOURCE_LABEL[k] || k}
          </span>
        ))}
      </div>
    </div>
  );
}

/** Horizontal proportion bar used by the funnel, SKU and duplicate panels. */
function Bar({ pct, color, height = 8 }) {
  return (
    <div style={{ height, background: '#f0f2f5', borderRadius: '4px', overflow: 'hidden' }}>
      <div style={{ width: `${Math.max(0, Math.min(100, pct))}%`, height: '100%', background: color, borderRadius: '4px' }} />
    </div>
  );
}

/** Drill-down overlay for one request or one user. */
function Detail({ title, subtitle, onClose, children }) {
  return (
    <div
      onClick={onClose}
      style={{
        position: 'fixed', inset: 0, background: 'rgba(18,18,18,0.45)',
        zIndex: 1000, display: 'flex', alignItems: 'flex-start',
        justifyContent: 'center', padding: '48px 20px', overflowY: 'auto',
      }}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="card"
        style={{ maxWidth: '900px', width: '100%', maxHeight: '85vh', overflowY: 'auto' }}
      >
        <div className="card-header">
          <div>
            <div className="card-title">{title}</div>
            {subtitle && (
              <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '3px' }}>
                {subtitle}
              </div>
            )}
          </div>
          <button className="btn btn-ghost" style={{ padding: '6px 12px' }} onClick={onClose}>
            Close
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}

export default function ApiUsage() {
  const [range, setRange] = useState('7d');
  const [provider, setProvider] = useState('');
  const [ingest, setIngest] = useState('');
  const [userFilter, setUserFilter] = useState('');
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState('');

  const [summary, setSummary] = useState(null);
  const [series, setSeries] = useState(null);
  const [funnel, setFunnel] = useState([]);
  const [breakdown, setBreakdown] = useState({ operations: [], free_tier: [] });
  const [dupes, setDupes] = useState({ keys: [], total_recoverable_usd: 0 });
  const [users, setUsers] = useState([]);
  const [health, setHealth] = useState({ by_status: [], recent_failures: [] });
  const [events, setEvents] = useState([]);
  const [pipeline, setPipeline] = useState(null);
  const [tailFilter, setTailFilter] = useState('');
  const [alerts, setAlerts] = useState({ alerts: [], open_counts: {} });
  const [spend, setSpend] = useState(null);
  const [routes, setRoutes] = useState([]);
  const [tokens, setTokens] = useState({ usage: [], total_tokens: 0 });
  const [coverage, setCoverage] = useState([]);
  const [recon, setRecon] = useState(null);
  const [uploading, setUploading] = useState(false);
  // Drill-downs. Null = closed; the modal renders whichever is set.
  const [reqDetail, setReqDetail] = useState(null);
  const [userDetail, setUserDetail] = useState(null);
  const [detailLoading, setDetailLoading] = useState(false);

  const activeRange = RANGES.find((r) => r.key === range) || RANGES[1];

  // Bumped by the Refresh button and by the 24h auto-poll to re-trigger a load.
  const [reloadToken, setReloadToken] = useState(0);
  const refresh = useCallback(() => setReloadToken((n) => n + 1), []);

  // Fetching lives inside the effect with a cancellation flag rather than in a
  // callback the effect invokes. Two reasons: switching range quickly would
  // otherwise let a slow earlier response land after a newer one and overwrite
  // it, and calling setState synchronously from an effect body causes a
  // cascading render.
  useEffect(() => {
    let cancelled = false;
    const hours = activeRange.hours;

    (async () => {
      setLoading(true);
      setErr('');
      const to = new Date();
      const from = new Date(to.getTime() - hours * 3600 * 1000);
      const q = `from=${from.toISOString()}&to=${to.toISOString()}`
        + `${provider ? `&provider=${provider}` : ''}${ingest ? `&ingest=${ingest}` : ''}`;
      try {
        const [s, ts, f, b, d, u, h, ev, pl, al, sp, rt, tk, cv, rc] = await Promise.all([
          apiGet(`/admin/telemetry/summary?${q}`),
          apiGet(`/admin/telemetry/timeseries?${q}&group_by=served_from`),
          apiGet(`/admin/telemetry/funnel?${q}${userFilter ? `&user_id=${userFilter}` : ''}`),
          apiGet(`/admin/telemetry/breakdown?${q}`),
          apiGet(`/admin/telemetry/duplicates?${q}&limit=15${userFilter ? `&user_id=${userFilter}` : ''}`),
          apiGet(`/admin/telemetry/users?${q}&limit=10`),
          apiGet(`/admin/telemetry/errors?${q}`),
          apiGet(`/admin/telemetry/events?${q}&page_size=40${tailFilter ? `&operation=${encodeURIComponent(tailFilter)}` : ''}${userFilter ? `&user_id=${userFilter}` : ''}`),
          apiGet('/admin/telemetry/pipeline'),
          apiGet('/admin/telemetry/alerts?only_open=true&limit=10'),
          apiGet('/admin/telemetry/spend'),
          apiGet(`/admin/telemetry/routes?${q}${userFilter ? `&user_id=${userFilter}` : ''}`),
          apiGet(`/admin/telemetry/tokens?${q}`),
          apiGet('/admin/telemetry/coverage'),
          apiGet(`/admin/telemetry/billing/reconcile?${q}`),
        ]);
        if (cancelled) return;
        setSummary(s); setSeries(ts); setFunnel(f.operations || []);
        setBreakdown(b); setDupes(d); setUsers(u.users || []);
        setHealth(h); setEvents(ev.events || []); setPipeline(pl);
        setAlerts(al); setSpend(sp);
        setRoutes(rt.routes || []); setTokens(tk); setCoverage(cv.sources || []);
        setRecon(rc);
      } catch (e) {
        if (!cancelled) setErr(e.message || 'Could not load telemetry.');
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();

    return () => { cancelled = true; };
  }, [activeRange.hours, provider, ingest, userFilter, tailFilter, reloadToken]);

  // Only the 24-hour view is worth polling; re-running the 90-day rollup
  // queries every half minute would be churn for no new information.
  useEffect(() => {
    if (range !== '24h') return undefined;
    const id = setInterval(refresh, 30000);
    return () => clearInterval(id);
  }, [range, refresh]);

  const openRequest = async (rid) => {
    if (!rid) return;
    setDetailLoading(true); setUserDetail(null);
    try {
      setReqDetail(await apiGet(`/admin/telemetry/request/${rid}`));
    } catch (e) { setErr(e.message || 'Could not load request detail.'); }
    finally { setDetailLoading(false); }
  };

  const openUser = async (uid) => {
    if (!uid) return;
    setDetailLoading(true); setReqDetail(null);
    const to = new Date();
    const from = new Date(to.getTime() - activeRange.hours * 3600 * 1000);
    try {
      setUserDetail(await apiGet(
        `/admin/telemetry/user/${uid}?from=${from.toISOString()}&to=${to.toISOString()}`));
    } catch (e) { setErr(e.message || 'Could not load user detail.'); }
    finally { setDetailLoading(false); }
  };

  const uploadBilling = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true); setErr('');
    try {
      const body = new FormData();
      body.append('file', file);
      const res = await fetch(`${API_BASE}/admin/telemetry/billing/import?currency=INR`, {
        method: 'POST', body,
        headers: { Authorization: `Bearer ${localStorage.getItem('admin_token')}` },
      });
      const j = await res.json();
      if (!res.ok) throw new Error(j.detail || 'Import failed');
      // Rates are re-derived from what Google actually charged, so the estimate
      // stops being a guess the moment real data lands.
      await apiPost('/admin/telemetry/billing/calibrate');
      refresh();
    } catch (e2) {
      setErr(e2.message || 'Could not import billing CSV.');
    } finally {
      setUploading(false);
      e.target.value = '';
    }
  };

  const ackAlert = async (id) => {
    try {
      await apiPost(`/admin/telemetry/alerts/${id}/ack`);
      refresh();
    } catch (e) {
      setErr(e.message || 'Could not acknowledge alert.');
    }
  };

  // A plain <a href> cannot carry the admin Bearer token, so the endpoint would
  // reject it. Fetch with auth, then hand the browser a blob to save.
  const [exporting, setExporting] = useState(false);
  const downloadCsv = async () => {
    setExporting(true);
    try {
      const to = new Date();
      const from = new Date(to.getTime() - activeRange.hours * 3600 * 1000);
      const qs = `from=${from.toISOString()}&to=${to.toISOString()}${provider ? `&provider=${provider}` : ''}`;
      const res = await fetch(
        `${API_BASE}/admin/telemetry/export.csv?${qs}`,
        { headers: { Authorization: `Bearer ${localStorage.getItem('admin_token')}` } },
      );
      if (!res.ok) throw new Error(`Export failed (${res.status})`);
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `api_events_${from.toISOString().slice(0, 10)}.csv`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch (e) {
      setErr(e.message || 'Export failed.');
    } finally {
      setExporting(false);
    }
  };

  const reqDelta = summary ? pctDelta(summary.requests, summary.prev_requests) : null;
  const costDelta = summary ? pctDelta(summary.est_cost_usd, summary.prev_est_cost_usd) : null;

  // An operation with real volume that never hits a cache is the actionable
  // case — it is the shape the Find Place spend had.
  const uncached = funnel.filter((o) => o.served_free_pct === 0 && o.est_cost_usd > 0);

  const openAlerts = alerts.alerts || [];

  return (
    <div>
      {/* ── Alerts ───────────────────────────────────────────────── */}
      {openAlerts.length > 0 && (
        <div style={{ display: 'grid', gap: '10px', marginBottom: '20px' }}>
          {openAlerts.map((a) => (
            <div
              key={a.id}
              className="card"
              style={{
                borderLeft: `4px solid ${a.severity === 'critical' ? 'var(--danger)' : 'var(--warning)'}`,
                display: 'flex', alignItems: 'center', gap: '14px', padding: '16px 20px',
              }}
            >
              <span className={`badge ${a.severity === 'critical' ? 'badge-red' : 'badge-yellow'}`}>
                {a.severity}
              </span>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: '13.5px', fontWeight: 600 }}>{a.message}</div>
                <div style={{ fontSize: '11.5px', color: 'var(--text-muted)', marginTop: '2px' }}>
                  {a.rule} · {a.subject} · {new Date(a.created_at).toLocaleString()}
                </div>
              </div>
              <button className="btn btn-ghost" style={{ padding: '6px 12px', fontSize: '12px' }} onClick={() => ackAlert(a.id)}>
                Dismiss
              </button>
            </div>
          ))}
        </div>
      )}

      {/* ── Billing reconciliation ───────────────────────────────── */}
      <div className="card" style={{ marginBottom: '20px',
        borderLeft: `4px solid ${recon?.configured ? 'var(--accent)' : 'var(--danger)'}` }}>
        <div className="card-header">
          <div className="card-title">Estimated cost vs actual bill</div>
          <label className="btn btn-ghost" style={{ padding: '8px 14px', cursor: 'pointer', margin: 0 }}>
            {uploading ? 'Importing…' : 'Import billing CSV'}
            <input type="file" accept=".csv" onChange={uploadBilling} style={{ display: 'none' }} />
          </label>
        </div>

        {!recon?.configured ? (
          <>
            <p style={{ color: 'var(--danger)', fontSize: '13.5px', fontWeight: 600 }}>
              Cost figures on this page are unverified estimates.
            </p>
            <p style={{ color: 'var(--text-secondary)', fontSize: '13.5px', marginTop: '8px' }}>
              They come from per-call rates that nothing has checked against a real invoice.
              In Google Cloud Console go to <strong>Billing → Reports</strong>, group by
              <strong> SKU</strong> (not Service — a service total has no usage column, and
              without usage there is no way to derive a rate), then Download CSV and import it
              here. Rates are recalculated from what you were actually charged.
            </p>
          </>
        ) : (
          <>
            <p style={{ color: 'var(--text-secondary)', fontSize: '13px', marginBottom: '14px' }}>
              {num(recon.imported_rows)} billing rows imported, covering {recon.coverage.from} → {recon.coverage.to}.
              Converted at {recon.fx_to_usd} per USD. A ratio far from 1.0 means the rate for that
              operation is wrong, and every figure derived from it with it.
            </p>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr><th>Operation</th><th>Our calls</th><th>Billed units</th><th>Estimated</th><th>Actual</th><th>Over by</th><th>Real cost / unit</th></tr>
                </thead>
                <tbody>
                  {(recon.operations || []).slice(0, 10).map((o, i) => (
                    <tr key={i}>
                      <td style={{ fontWeight: 600, fontSize: '12.5px' }}>{o.operation || '—'}</td>
                      <td>{num(o.our_calls)}</td>
                      <td>{o.billed_usage ? num(o.billed_usage) : '—'}</td>
                      <td>{usd(o.estimated)}</td>
                      <td style={{ fontWeight: 700 }}>{usd(o.actual_gross_usd)}</td>
                      <td>
                        {o.ratio == null ? '—' : (
                          <span className={`badge ${o.ratio > 2 || o.ratio < 0.5 ? 'badge-red' : 'badge-green'}`}>
                            {o.ratio}×
                          </span>
                        )}
                      </td>
                      <td style={{ fontFamily: 'ui-monospace, Menlo, monospace', fontSize: '11.5px' }}>
                        {o.actual_unit_cost_usd != null ? `$${o.actual_unit_cost_usd.toFixed(8)}` : '—'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>

      {/* ── Data coverage ────────────────────────────────────────── */}
      {coverage.some((c) => c.ingest === 'legacy' && c.rows > 0) && (
        <div className="card" style={{ marginBottom: '20px', borderLeft: '4px solid var(--warning)' }}>
          <div className="card-header"><div className="card-title">What this data can tell you</div></div>
          <div className="table-wrap">
            <table>
              <thead><tr><th>Source</th><th>Rows</th><th>Period</th><th>Cost basis</th><th>Cache tier</th><th>Tokens</th><th>Dedup</th></tr></thead>
              <tbody>
                {coverage.map((c) => (
                  <tr key={c.ingest}>
                    <td><span className={`badge ${c.ingest === 'live' ? 'badge-green' : 'badge-yellow'}`}>{c.ingest}</span></td>
                    <td>{num(c.rows)}</td>
                    <td style={{ fontSize: '12px' }}>
                      {c.lo ? new Date(c.lo).toLocaleDateString() : '—'} → {c.hi ? new Date(c.hi).toLocaleDateString() : '—'}
                    </td>
                    <td style={{ fontSize: '12.5px' }}>{c.cost_basis}</td>
                    <td>{c.has_cache_data ? 'recorded' : <span style={{ color: 'var(--text-muted)' }}>not recorded</span>}</td>
                    <td>{c.has_token_data ? 'recorded' : <span style={{ color: 'var(--text-muted)' }}>not recorded</span>}</td>
                    <td>{c.has_dedup_data ? 'recorded' : <span style={{ color: 'var(--text-muted)' }}>not recorded</span>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p style={{ marginTop: '12px', fontSize: '13px', color: 'var(--text-secondary)' }}>
            Legacy rows were reconstructed from the old request log, which was written
            <em> before</em> each call was made and never recorded the outcome. Their volume is
            real. Their cost is <strong>every attempt priced at list</strong> — an upper bound,
            since failed calls were not billed and the free tier is applied separately. Cache
            keys and token counts were never captured, so the dedup and AI panels stay empty for
            that period. Switch the filter to <strong>Measured only</strong> for figures that
            come from recorded outcomes.
          </p>
        </div>
      )}

      {/* ── Budget ───────────────────────────────────────────────── */}
      {spend && spend.monthly_budget_usd > 0 && (
        <div className="card" style={{ marginBottom: '20px' }}>
          <div className="card-header">
            <div className="card-title">Monthly budget</div>
            <span className={`badge ${spend.enforcing ? 'badge-green' : 'badge-yellow'}`}>
              {spend.enforcing ? 'enforcing' : 'alerts only'}
            </span>
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '13px', marginBottom: '8px' }}>
            <span>{usd(spend.month_to_date_usd)} of {usd(spend.monthly_budget_usd)}</span>
            <span style={{ color: spend.over_budget ? 'var(--danger)' : 'var(--text-secondary)', fontWeight: 700 }}>
              {spend.pct_consumed}%
            </span>
          </div>
          <Bar
            pct={spend.pct_consumed || 0}
            color={spend.over_budget ? 'var(--danger)' : (spend.pct_consumed || 0) > 80 ? 'var(--warning)' : 'var(--accent)'}
            height={10}
          />
          {spend.over_budget && (
            <p style={{ marginTop: '10px', fontSize: '13px', color: 'var(--danger)', fontWeight: 600 }}>
              {spend.enforcing
                ? 'Budget reached — paid calls are being refused and cached results served instead.'
                : 'Budget reached, but enforcement is off — calls are still being paid for.'}
            </p>
          )}
        </div>
      )}

      {/* ── Controls ─────────────────────────────────────────────── */}
      <div className="card" style={{ marginBottom: '20px' }}>
        <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap', alignItems: 'center' }}>
          <div style={{ display: 'flex', gap: '6px' }}>
            {RANGES.map((r) => (
              <button
                key={r.key}
                className={`btn ${range === r.key ? 'btn-primary' : 'btn-ghost'}`}
                style={{ padding: '8px 14px', fontSize: '13px' }}
                onClick={() => setRange(r.key)}
              >
                {r.label}
              </button>
            ))}
          </div>
          <select
            className="form-input"
            style={{ width: 'auto', minWidth: '160px' }}
            value={provider}
            onChange={(e) => setProvider(e.target.value)}
          >
            <option value="">All providers</option>
            <option value="google_maps">Google Maps</option>
            <option value="gemini">Gemini</option>
            <option value="geoapify">Geoapify</option>
            <option value="mapbox">Mapbox</option>
            <option value="serpapi">SerpAPI</option>
            <option value="internal">Internal (cache/DB)</option>
          </select>
          <select
            className="form-input"
            style={{ width: 'auto', minWidth: '170px' }}
            value={ingest}
            onChange={(e) => setIngest(e.target.value)}
            title="Legacy rows were reconstructed from the old log and carry estimated cost"
          >
            <option value="">All data</option>
            <option value="live">Measured only</option>
            <option value="legacy">Historical only</option>
          </select>
          <select
            className="form-input"
            style={{ width: 'auto', minWidth: '210px' }}
            value={userFilter}
            onChange={(e) => setUserFilter(e.target.value)}
          >
            <option value="">All users</option>
            {users.map((u) => (
              <option key={u.user_id} value={u.user_id}>
                {(u.display_name || u.email || u.user_id).slice(0, 30)} — {usd(u.est_cost_usd)}
              </option>
            ))}
          </select>
          <div style={{ marginLeft: 'auto', display: 'flex', gap: '8px', alignItems: 'center' }}>
            {summary && (
              <span className="badge badge-ghost" title="Wide ranges read the hourly rollup rather than raw events">
                {summary.source === 'rollup' ? 'rollup' : 'live rows'}
              </span>
            )}
            <button className="btn btn-ghost" style={{ padding: '8px 14px' }} onClick={refresh}>
              <RefreshIcon size={14} /> Refresh
            </button>
          </div>
        </div>
      </div>

      {err && (
        <div className="card" style={{ marginBottom: '20px', borderColor: 'rgba(229,57,53,0.3)' }}>
          <span style={{ color: 'var(--danger)', fontWeight: 700 }}>{err}</span>
        </div>
      )}

      {userFilter && (
        <div className="card" style={{ marginBottom: '20px', borderLeft: '4px solid var(--accent)',
                                       display: 'flex', alignItems: 'center', gap: '14px' }}>
          <span className="badge badge-blue">Filtered to one user</span>
          <span style={{ fontSize: '13.5px', color: 'var(--text-secondary)' }}>
            {(users.find((u) => u.user_id === userFilter) || {}).email || userFilter}
          </span>
          <div style={{ marginLeft: 'auto', display: 'flex', gap: '8px' }}>
            <button className="btn btn-ghost" style={{ padding: '6px 12px', fontSize: '12px' }}
                    onClick={() => openUser(userFilter)}>
              Full profile
            </button>
            <button className="btn btn-ghost" style={{ padding: '6px 12px', fontSize: '12px' }}
                    onClick={() => setUserFilter('')}>
              Clear
            </button>
          </div>
        </div>
      )}

      {/* ── Tiles ────────────────────────────────────────────────── */}
      <div className="stats-grid">
        <div className="stat-card">
          <div className="stat-icon"><CompassIcon size={24} style={{ color: 'var(--accent)' }} /></div>
          <div className="stat-value">{num(summary?.requests)}</div>
          <div className="stat-label">Requests</div>
          {reqDelta !== null && (
            <span className={`stat-change ${reqDelta >= 0 ? 'up' : 'down'}`} style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
              {reqDelta >= 0 ? <TrendingUpIcon size={12} /> : <TrendingDownIcon size={12} />}
              {Math.abs(reqDelta).toFixed(1)}% vs previous
            </span>
          )}
        </div>

        <div className="stat-card">
          <div className="stat-icon"><DollarIcon size={24} style={{ color: 'var(--danger)' }} /></div>
          <div className="stat-value">{num(summary?.billable_calls)}</div>
          <div className="stat-label">Billable calls</div>
          <span className="stat-change" style={{ background: 'rgba(229,57,53,0.06)', color: 'var(--danger)' }}>
            {summary && summary.requests
              ? `${((summary.billable_calls / summary.requests) * 100).toFixed(1)}% of requests`
              : '—'}
          </span>
        </div>

        <div className="stat-card">
          <div className="stat-icon"><DollarIcon size={24} style={{ color: 'var(--warning)' }} /></div>
          <div className="stat-value">{usd(summary?.est_cost_usd)}</div>
          <div className="stat-label">
            {ingest === 'live' ? 'Measured cost' : 'Estimated cost'}
          </div>
          {costDelta !== null && (
            <span className={`stat-change ${costDelta >= 0 ? 'down' : 'up'}`} style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
              {costDelta >= 0 ? <TrendingUpIcon size={12} /> : <TrendingDownIcon size={12} />}
              {Math.abs(costDelta).toFixed(1)}% vs previous
            </span>
          )}
        </div>

        <div className="stat-card">
          <div className="stat-icon"><TrendingUpIcon size={24} style={{ color: 'var(--success)' }} /></div>
          <div className="stat-value">{summary ? `${summary.served_free_pct}%` : '—'}</div>
          <div className="stat-label">Served without paying</div>
          <span className="stat-change up">
            {summary ? `${summary.error_pct}% errors` : '—'}
          </span>
        </div>
      </div>

      {/* ── Uncached spend callout ───────────────────────────────── */}
      {uncached.length > 0 && (
        <div className="card" style={{ marginTop: '20px', borderLeft: '4px solid var(--danger)' }}>
          <div className="card-header"><div className="card-title">Paid operations with no cache</div></div>
          <p style={{ color: 'var(--text-secondary)', fontSize: '13.5px', marginBottom: '12px' }}>
            Every one of these requests reached a provider. Putting a cache in front of the
            busiest is the highest-value change available.
          </p>
          <div style={{ display: 'flex', gap: '10px', flexWrap: 'wrap' }}>
            {uncached.map((o) => (
              <span key={o.operation} className="badge badge-red">
                {o.operation} — {num(o.total)} calls, {usd(o.est_cost_usd)}
              </span>
            ))}
          </div>
        </div>
      )}

      {/* ── Timeseries ───────────────────────────────────────────── */}
      <div className="card" style={{ marginTop: '20px' }}>
        <div className="card-header">
          <div className="card-title">Requests over time</div>
          <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
            stacked by source · per {series?.bucket || 'hour'}
          </span>
        </div>
        <StackedBars points={series?.points} />
      </div>

      {/* ── Funnel + SKU cost ────────────────────────────────────── */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(360px, 1fr))', gap: '20px', marginTop: '20px' }}>
        <div className="card">
          <div className="card-header"><div className="card-title">Where requests were served from</div></div>
          <div style={{ display: 'grid', gap: '16px' }}>
            {funnel.length === 0 && <div className="empty-state">No data in this window.</div>}
            {funnel.map((o) => (
              <div key={o.operation}>
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '6px', fontSize: '13px' }}>
                  <strong>{o.operation}</strong>
                  <span style={{ color: o.served_free_pct === 0 ? 'var(--danger)' : 'var(--success)', fontWeight: 700 }}>
                    {o.served_free_pct}% free
                  </span>
                </div>
                <div style={{ display: 'flex', height: '10px', borderRadius: '4px', overflow: 'hidden', background: '#f0f2f5' }}>
                  {Object.entries(o.sources).map(([src, n]) => (
                    <div
                      key={src}
                      title={`${SOURCE_LABEL[src] || src}: ${num(n)}`}
                      style={{ width: `${(n / o.total) * 100}%`, background: SOURCE_COLOR[src] || '#c9d4dd' }}
                    />
                  ))}
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: '5px', fontSize: '11.5px', color: 'var(--text-muted)' }}>
                  <span>{num(o.total)} requests</span>
                  <span>{usd(o.est_cost_usd)}</span>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="card">
          <div className="card-header">
            <div className="card-title">Free tier consumed this month</div>
          </div>
          <p style={{ color: 'var(--text-secondary)', fontSize: '13px', marginBottom: '14px' }}>
            Spend stays low while these bars are short. An operation crossing 100% starts
            billing every further call.
          </p>
          <div style={{ display: 'grid', gap: '14px' }}>
            {breakdown.free_tier.filter((t) => t.used_this_month > 0).length === 0 && (
              <div className="empty-state">Nothing billable yet this month.</div>
            )}
            {breakdown.free_tier
              .filter((t) => t.used_this_month > 0)
              .slice(0, 8)
              .map((t) => (
                <div key={t.sku}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '5px', fontSize: '12.5px' }}>
                    <strong>{t.sku}</strong>
                    <span style={{ color: 'var(--text-secondary)' }}>
                      {num(t.used_this_month)} / {t.free_tier_monthly ? num(t.free_tier_monthly) : '∞'}
                    </span>
                  </div>
                  <Bar
                    pct={t.pct_consumed || 0}
                    color={(t.pct_consumed || 0) > 90 ? 'var(--danger)' : (t.pct_consumed || 0) > 60 ? 'var(--warning)' : 'var(--accent)'}
                  />
                </div>
              ))}
          </div>
        </div>
      </div>

      {/* ── Routes & fan-out ─────────────────────────────────────── */}
      <div className="card" style={{ marginTop: '20px' }}>
        <div className="card-header">
          <div className="card-title">Which screens generate the work</div>
          <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
            fan-out = upstream calls per user action
          </span>
        </div>
        <p style={{ color: 'var(--text-secondary)', fontSize: '13.5px', marginBottom: '14px' }}>
          A high fan-out is a design problem, not a traffic problem: one tap firing fifteen
          paid lookups costs fifteen times what it looks like it should.
        </p>
        <div className="table-wrap">
          <table>
            <thead>
              <tr><th>Endpoint</th><th>Actions</th><th>Calls</th><th>Fan-out</th><th>Paid</th><th>Tokens</th><th>Cost</th></tr>
            </thead>
            <tbody>
              {routes.length === 0 && (
                <tr><td colSpan={7}><div className="empty-state">No routed traffic in this window.</div></td></tr>
              )}
              {routes.slice(0, 15).map((r) => (
                <tr key={r.route}>
                  <td style={{ fontFamily: 'ui-monospace, Menlo, monospace', fontSize: '12px' }}>{r.route}</td>
                  <td>{num(r.actions)}</td>
                  <td>{num(r.calls)}</td>
                  <td>
                    <span className={`badge ${r.fan_out > 5 ? 'badge-red' : r.fan_out > 2 ? 'badge-yellow' : 'badge-ghost'}`}>
                      {r.fan_out ?? '—'}×
                    </span>
                  </td>
                  <td style={{ color: r.upstream ? 'var(--danger)' : 'var(--text-muted)' }}>{num(r.upstream)}</td>
                  <td>{r.tokens ? num(r.tokens) : '—'}</td>
                  <td style={{ fontWeight: 700 }}>{usd(r.cost)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* ── AI tokens ────────────────────────────────────────────── */}
      <div className="card" style={{ marginTop: '20px' }}>
        <div className="card-header">
          <div className="card-title">AI token usage</div>
          <span className="badge badge-ghost">{num(tokens.total_tokens)} tokens</span>
        </div>
        <p style={{ color: 'var(--text-secondary)', fontSize: '13.5px', marginBottom: '14px' }}>
          Gemini bills per token, not per call — one long itinerary prompt can cost more than a
          hundred short lookups, so a call count says nothing useful here.
        </p>
        <div className="table-wrap">
          <table>
            <thead>
              <tr><th>Provider</th><th>Operation</th><th>Calls</th><th>Prompt</th><th>Completion</th><th>Avg / call</th><th>Cost</th></tr>
            </thead>
            <tbody>
              {tokens.usage.length === 0 && (
                <tr><td colSpan={7}>
                  <div className="empty-state">
                    No token data for this period. Historical rows never captured token
                    counts, and no AI call has succeeded since token recording went live —
                    the Gemini key is currently invalid.
                  </div>
                </td></tr>
              )}
              {tokens.usage.map((t, i) => (
                <tr key={i}>
                  <td>{t.provider}</td>
                  <td style={{ fontSize: '12.5px' }}>{t.operation}</td>
                  <td>{num(t.calls)}</td>
                  <td>{num(t.prompt_tokens)}</td>
                  <td>{num(t.completion_tokens)}</td>
                  <td>{num(t.avg_tokens)}</td>
                  <td style={{ fontWeight: 700 }}>{usd(t.cost)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* ── Duplicates ───────────────────────────────────────────── */}
      <div className="card" style={{ marginTop: '20px' }}>
        <div className="card-header">
          <div className="card-title">Paid for more than once</div>
          <span className="badge badge-yellow">{usd(dupes.total_recoverable_usd)} recoverable</span>
        </div>
        <p style={{ color: 'var(--text-secondary)', fontSize: '13.5px', marginBottom: '14px' }}>
          These lookups were bought from a provider repeatedly. A working cache on the
          operation would have served every call after the first.
        </p>
        <div className="table-wrap">
          <table>
            <thead>
              <tr><th>Cache key</th><th>Operation</th><th>Times paid</th><th>Spent</th><th>Recoverable</th></tr>
            </thead>
            <tbody>
              {dupes.keys.length === 0 && (
                <tr><td colSpan={5}><div className="empty-state">
                    {ingest === 'live'
                      ? 'No repeat purchases — caching is holding.'
                      : 'Historical rows never captured cache keys, so repeats cannot be detected before today. This fills in as live traffic accumulates.'}
                  </div></td></tr>
              )}
              {dupes.keys.map((k) => (
                <tr key={`${k.operation}:${k.cache_key}`}>
                  <td style={{ fontFamily: 'ui-monospace, Menlo, monospace', fontSize: '12px' }}>{k.cache_key}</td>
                  <td>{k.operation}</td>
                  <td><span className="badge badge-red">{k.paid_times}×</span></td>
                  <td>{usd(k.spent_usd)}</td>
                  <td style={{ fontWeight: 700 }}>{usd(k.recoverable_usd)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* ── Top consumers + provider health ──────────────────────── */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(360px, 1fr))', gap: '20px', marginTop: '20px' }}>
        <div className="card">
          <div className="card-header"><div className="card-title">Top consumers</div></div>
          <div className="table-wrap">
            <table>
              <thead><tr><th>User</th><th>Calls</th><th>Billable</th><th>Cost</th></tr></thead>
              <tbody>
                {users.length === 0 && (
                  <tr><td colSpan={4}><div className="empty-state">No attributed usage yet.</div></td></tr>
                )}
                {users.map((u) => (
                  <tr key={u.user_id} className="clickable-row"
                      style={{ cursor: 'pointer' }}
                      onClick={() => openUser(u.user_id)}>
                    <td>
                      <div className="user-name">{u.display_name || '—'}</div>
                      <div style={{ fontSize: '11.5px', color: 'var(--text-muted)' }}>{u.email || u.user_id}</div>
                    </td>
                    <td>{num(u.calls)}</td>
                    <td>{num(u.billable_calls)}</td>
                    <td style={{ fontWeight: 700 }}>{usd(u.est_cost_usd)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        <div className="card">
          <div className="card-header"><div className="card-title">Provider health</div></div>
          <div className="table-wrap">
            <table>
              <thead><tr><th>Provider</th><th>Status</th><th>Calls</th></tr></thead>
              <tbody>
                {health.by_status.slice(0, 10).map((s, i) => {
                  const bad = ['REQUEST_DENIED', 'OVER_QUERY_LIMIT', 'INVALID_REQUEST', 'INVALID_ARGUMENT'].includes(s.status);
                  return (
                    <tr key={i}>
                      <td>{s.provider}</td>
                      <td><span className={`badge ${bad ? 'badge-red' : 'badge-green'}`}>{s.status}</span></td>
                      <td>{num(s.calls)}</td>
                    </tr>
                  );
                })}
                {health.by_status.length === 0 && (
                  <tr><td colSpan={3}><div className="empty-state">No provider calls in this window.</div></td></tr>
                )}
              </tbody>
            </table>
          </div>
          {health.by_status.some((s) => s.status === 'REQUEST_DENIED') && (
            <p style={{ marginTop: '12px', fontSize: '13px', color: 'var(--danger)', fontWeight: 600 }}>
              REQUEST_DENIED present — an API key is invalid, restricted, or over quota.
            </p>
          )}
        </div>
      </div>

      {/* ── Live tail ────────────────────────────────────────────── */}
      <div className="card" style={{ marginTop: '20px' }}>
        <div className="card-header">
          <div className="card-title">Recent events</div>
          <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
            <div style={{ position: 'relative' }}>
              <SearchIcon size={14} style={{ position: 'absolute', left: '10px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
              <input
                className="form-input"
                style={{ paddingLeft: '30px', width: '200px' }}
                placeholder="Filter by operation"
                value={tailFilter}
                onChange={(e) => setTailFilter(e.target.value)}
              />
            </div>
            <button className="btn btn-ghost" style={{ padding: '8px 14px' }} onClick={downloadCsv} disabled={exporting}>
              {exporting ? 'Exporting…' : 'Export CSV'}
            </button>
          </div>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr><th>Time</th><th>Route</th><th>Provider</th><th>Operation</th><th>Source</th><th>Status</th><th>Latency</th><th>Tokens</th><th>Cost</th><th>App</th></tr>
            </thead>
            <tbody>
              {events.length === 0 && (
                <tr><td colSpan={8}><div className="empty-state">No events recorded.</div></td></tr>
              )}
              {events.map((e, i) => (
                <tr key={i} className="clickable-row"
                    style={{ cursor: e.request_id ? 'pointer' : 'default' }}
                    onClick={() => openRequest(e.request_id)}
                    title={e.request_id ? 'Show every call this request made' : ''}>
                  <td style={{ fontSize: '12px', whiteSpace: 'nowrap' }}>{new Date(e.ts).toLocaleTimeString()}</td>
                  <td style={{ fontSize: '11.5px', fontFamily: 'ui-monospace, Menlo, monospace', color: 'var(--text-secondary)' }}>
                    {e.route ? e.route.replace('/api/v1', '') : '—'}
                  </td>
                  <td style={{ fontSize: '12.5px' }}>{e.provider}</td>
                  <td style={{ fontSize: '12.5px' }}>{e.operation}</td>
                  <td>
                    <span
                      className="badge"
                      style={{
                        background: `${SOURCE_COLOR[e.served_from]}14`,
                        color: SOURCE_COLOR[e.served_from] || 'var(--text-secondary)',
                      }}
                    >
                      {e.served_from}
                    </span>
                  </td>
                  <td style={{ fontSize: '12px' }}>{e.provider_status || e.http_status || '—'}</td>
                  <td style={{ fontSize: '12px' }}>
                    <ClockIcon size={11} style={{ verticalAlign: '-1px', marginRight: '3px', color: 'var(--text-muted)' }} />
                    {e.latency_ms ?? '—'} ms
                  </td>
                  <td style={{ fontSize: '12px' }}>{e.total_tokens ? num(e.total_tokens) : '—'}</td>
                  <td style={{ fontSize: '12px', fontWeight: e.billable ? 700 : 400, color: e.billable ? 'var(--danger)' : 'var(--text-muted)' }}>
                    {e.billable ? usd(e.est_cost_usd) : 'free'}
                  </td>
                  <td style={{ fontSize: '11.5px', color: 'var(--text-muted)' }}>
                    {e.platform || '—'} {e.app_version || ''}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* ── Pipeline health ──────────────────────────────────────── */}
      {pipeline && (
        <div className="card" style={{ marginTop: '20px' }}>
          <div className="card-header"><div className="card-title">Telemetry pipeline</div></div>
          <p style={{ color: 'var(--text-secondary)', fontSize: '13px', marginBottom: '12px' }}>
            Counters for the recorder itself. Non-zero drops mean this page is under-reporting,
            which is worse than it showing nothing.
          </p>
          <div style={{ display: 'flex', gap: '22px', flexWrap: 'wrap', fontSize: '13px' }}>
            {Object.entries(pipeline).map(([k, v]) => (
              <span key={k}>
                <strong style={{ color: k.startsWith('dropped') && v > 0 ? 'var(--danger)' : 'var(--text-primary)' }}>
                  {num(v)}
                </strong>
                <span style={{ color: 'var(--text-muted)', marginLeft: '5px' }}>{k.replace(/_/g, ' ')}</span>
              </span>
            ))}
          </div>
        </div>
      )}

      <p style={{ marginTop: '18px', fontSize: '12px', color: 'var(--text-muted)' }}>
        Costs are estimates from the editable SKU rate table, not billing data. Use the CSV
        export to reconcile against your provider invoice.
      </p>

      {loading && <div style={{ marginTop: '16px', color: 'var(--text-muted)', fontSize: '13px' }}>Loading…</div>}

      {/* ── Request drill-down ───────────────────────────────────── */}
      {reqDetail && (
        <Detail
          title="Request detail"
          subtitle={`${reqDetail.route || 'unknown route'} · ${new Date(reqDetail.started_at).toLocaleString()}`}
          onClose={() => setReqDetail(null)}
        >
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(120px,1fr))', gap: '12px', marginBottom: '18px' }}>
            {[
              ['Upstream calls', num(reqDetail.upstream_calls), reqDetail.upstream_calls ? 'var(--danger)' : undefined],
              ['Served cached', num(reqDetail.cached_calls), 'var(--success)'],
              ['Cost', usd(reqDetail.total_cost_usd)],
              ['Tokens', reqDetail.total_tokens ? num(reqDetail.total_tokens) : '—'],
              ['Total latency', `${num(reqDetail.total_latency_ms)} ms`],
            ].map(([label, value, color]) => (
              <div key={label} style={{ border: '1px solid var(--border)', borderRadius: '10px', padding: '12px' }}>
                <div style={{ fontSize: '18px', fontWeight: 700, color: color || 'var(--text-primary)' }}>{value}</div>
                <div style={{ fontSize: '10.5px', textTransform: 'uppercase', letterSpacing: '0.08em', color: 'var(--text-muted)', marginTop: '3px' }}>{label}</div>
              </div>
            ))}
          </div>
          <div style={{ fontSize: '12.5px', color: 'var(--text-secondary)', marginBottom: '10px' }}>
            {reqDetail.user_id
              ? <>User <code>{reqDetail.user_id}</code> · {reqDetail.platform || '—'} {reqDetail.app_version || ''}</>
              : 'Anonymous request'}
          </div>
          <div className="table-wrap">
            <table>
              <thead><tr><th>#</th><th>Provider</th><th>Operation</th><th>Source</th><th>Status</th><th>Latency</th><th>Tokens</th><th>Cost</th><th>Cache key</th></tr></thead>
              <tbody>
                {reqDetail.calls.map((c, i) => (
                  <tr key={i}>
                    <td>{i + 1}</td>
                    <td>{c.provider}</td>
                    <td style={{ fontSize: '12.5px' }}>{c.operation}</td>
                    <td>
                      <span className="badge" style={{ background: `${SOURCE_COLOR[c.served_from]}14`, color: SOURCE_COLOR[c.served_from] }}>
                        {c.served_from}
                      </span>
                    </td>
                    <td style={{ fontSize: '12px' }}>{c.provider_status || c.http_status || '—'}</td>
                    <td style={{ fontSize: '12px' }}>{c.latency_ms ?? '—'} ms</td>
                    <td style={{ fontSize: '12px' }}>{c.total_tokens ? num(c.total_tokens) : '—'}</td>
                    <td style={{ fontWeight: c.billable ? 700 : 400, color: c.billable ? 'var(--danger)' : 'var(--text-muted)' }}>
                      {c.billable ? usd(c.est_cost_usd) : 'free'}
                    </td>
                    <td style={{ fontFamily: 'ui-monospace, Menlo, monospace', fontSize: '11px', color: 'var(--text-muted)' }}>
                      {c.cache_key || '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Detail>
      )}

      {/* ── User drill-down ──────────────────────────────────────── */}
      {userDetail && (
        <Detail
          title={userDetail.user.display_name || userDetail.user.email || 'User'}
          subtitle={userDetail.user.email || ''}
          onClose={() => setUserDetail(null)}
        >
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(110px,1fr))', gap: '12px', marginBottom: '18px' }}>
            {[
              ['Actions', num(userDetail.totals.actions)],
              ['API calls', num(userDetail.totals.requests)],
              ['Paid calls', num(userDetail.totals.billable)],
              ['Cost', usd(userDetail.totals.cost)],
              ['Tokens', userDetail.totals.tokens ? num(userDetail.totals.tokens) : '—'],
              ['Active days', num(userDetail.totals.active_days)],
            ].map(([label, value]) => (
              <div key={label} style={{ border: '1px solid var(--border)', borderRadius: '10px', padding: '12px' }}>
                <div style={{ fontSize: '17px', fontWeight: 700 }}>{value}</div>
                <div style={{ fontSize: '10.5px', textTransform: 'uppercase', letterSpacing: '0.08em', color: 'var(--text-muted)', marginTop: '3px' }}>{label}</div>
              </div>
            ))}
          </div>

          <h4 style={{ fontSize: '13px', margin: '0 0 8px' }}>Endpoints used — and where each was answered</h4>
          <div className="table-wrap" style={{ marginBottom: '18px' }}>
            <table>
              <thead><tr><th>Endpoint</th><th>Calls</th><th>From cache/DB</th><th>Paid to provider</th><th>Tokens</th><th>Cost</th></tr></thead>
              <tbody>
                {(userDetail.by_endpoint || []).map((e) => (
                  <tr key={e.operation}>
                    <td style={{ fontSize: '12.5px', fontWeight: 600 }}>{e.operation}</td>
                    <td>{num(e.calls)}</td>
                    <td>
                      <span style={{ color: 'var(--success)' }}>{num(e.local_calls)}</span>
                      <span style={{ color: 'var(--text-muted)', fontSize: '11px', marginLeft: '5px' }}>
                        {e.local_pct}%
                      </span>
                    </td>
                    <td style={{ color: e.paid_calls ? 'var(--danger)' : 'var(--text-muted)' }}>{num(e.paid_calls)}</td>
                    <td>{e.tokens ? num(e.tokens) : '—'}</td>
                    <td style={{ fontWeight: 700 }}>{usd(e.cost)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <h4 style={{ fontSize: '13px', margin: '0 0 8px' }}>Screens used</h4>
          <div className="table-wrap" style={{ marginBottom: '18px' }}>
            <table>
              <thead><tr><th>Endpoint</th><th>Actions</th><th>Calls</th><th>Cost</th></tr></thead>
              <tbody>
                {userDetail.by_route.map((r) => (
                  <tr key={r.route}>
                    <td style={{ fontFamily: 'ui-monospace, Menlo, monospace', fontSize: '11.5px' }}>{r.route}</td>
                    <td>{num(r.actions)}</td>
                    <td>{num(r.calls)}</td>
                    <td>{usd(r.cost)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <h4 style={{ fontSize: '13px', margin: '0 0 8px' }}>Recent actions</h4>
          <div className="table-wrap">
            <table>
              <thead><tr><th>When</th><th>Endpoint</th><th>Calls</th><th>Cost</th></tr></thead>
              <tbody>
                {userDetail.recent_actions.map((a) => (
                  <tr key={a.request_id} className="clickable-row" style={{ cursor: 'pointer' }}
                      onClick={() => openRequest(a.request_id)}>
                    <td style={{ fontSize: '12px' }}>{new Date(a.ts).toLocaleString()}</td>
                    <td style={{ fontFamily: 'ui-monospace, Menlo, monospace', fontSize: '11.5px' }}>{a.route || '—'}</td>
                    <td>{num(a.calls)}</td>
                    <td>{usd(a.cost)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Detail>
      )}

      {detailLoading && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(18,18,18,0.25)', zIndex: 999,
                      display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff' }}>
          Loading detail…
        </div>
      )}
    </div>
  );
}
