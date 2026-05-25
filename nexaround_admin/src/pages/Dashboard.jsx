import { useState, useCallback } from 'react';
import { useApi, apiGet } from '../api';
import { CompassIcon, MapPinIcon, CreditCardIcon, ClockIcon, TrendingUpIcon, TrendingDownIcon } from '../components/Icons';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const API_KEY_MAP = {
  'Google Maps API': 'google_maps',
  'Mapbox API': 'mapbox',
  'Gemini API': 'gemini',
};

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
    return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
  } catch {
    return isoStr;
  }
}

function BreakdownModal({ api, color, onClose }) {
  const [breakdown, setBreakdown] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const apiKey = API_KEY_MAP[api.name] || api.name;

  const fetchBreakdown = useCallback(() => {
    setLoading(true);
    setError(null);
    apiGet(`/admin/api-breakdown/${apiKey}`)
      .then(data => { setBreakdown(data); setLoading(false); })
      .catch(err => { setError(err.message); setLoading(false); });
  }, [apiKey]);

  // Fetch on first render
  useState(() => { fetchBreakdown(); }, []);

  return (
    <div
      style={{
        position: 'fixed', inset: 0, zIndex: 9999,
        background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(4px)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}
      onClick={onClose}
    >
      <div
        style={{
          background: 'var(--bg-card)', borderRadius: '20px',
          border: '1px solid var(--border)', width: '480px', maxWidth: '92vw',
          padding: '28px', boxShadow: '0 24px 64px rgba(0,0,0,0.5)',
          maxHeight: '80vh', overflowY: 'auto',
        }}
        onClick={e => e.stopPropagation()}
      >
        {/* Header */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
              <div style={{ width: '12px', height: '12px', borderRadius: '50%', background: color, boxShadow: `0 0 8px ${color}` }} />
              <span style={{ fontWeight: 800, fontSize: '16px', color: 'var(--text-primary)' }}>{api.name}</span>
            </div>
            <div style={{ fontSize: '12px', color: 'var(--text-secondary)', marginTop: '4px' }}>
              Endpoint-level request breakdown
            </div>
          </div>
          <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
            <button
              onClick={fetchBreakdown}
              style={{
                background: 'var(--bg-dark)', border: '1px solid var(--border)',
                borderRadius: '8px', padding: '6px 12px', color: 'var(--text-secondary)',
                cursor: 'pointer', fontSize: '12px', fontWeight: 600,
                display: 'flex', alignItems: 'center', gap: '6px',
              }}
              title="Refresh breakdown"
            >
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 .49-3.61"/>
              </svg>
              Refresh
            </button>
            <button
              onClick={onClose}
              style={{
                background: 'none', border: 'none', color: 'var(--text-secondary)',
                cursor: 'pointer', fontSize: '20px', lineHeight: 1, padding: '4px',
              }}
            >×</button>
          </div>
        </div>

        {loading && (
          <div style={{ textAlign: 'center', padding: '30px', color: 'var(--text-secondary)' }}>
            Loading breakdown...
          </div>
        )}
        {error && (
          <div style={{ color: 'var(--error)', fontSize: '13px', padding: '12px', background: 'rgba(239,68,68,0.1)', borderRadius: '8px' }}>
            Error: {error}
          </div>
        )}
        {breakdown && !loading && (
          <>
            {/* Total badge */}
            <div style={{
              background: 'var(--bg-dark)', borderRadius: '12px', padding: '12px 16px',
              display: 'flex', justifyContent: 'space-between', alignItems: 'center',
              marginBottom: '16px', border: `1px solid ${color}33`,
            }}>
              <span style={{ fontSize: '13px', color: 'var(--text-secondary)', fontWeight: 600 }}>Total Requests (All Time)</span>
              <span style={{ fontSize: '22px', fontWeight: 800, color, letterSpacing: '-0.5px' }}>
                {breakdown.total.toLocaleString()}
              </span>
            </div>

            {/* Endpoint rows */}
            {breakdown.endpoints.length === 0 ? (
              <div style={{ textAlign: 'center', padding: '20px', color: 'var(--text-secondary)', fontSize: '13px' }}>
                No requests logged yet.
              </div>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                {breakdown.endpoints.map((ep, i) => {
                  const pct = breakdown.total > 0 ? Math.round((ep.count / breakdown.total) * 100) : 0;
                  return (
                    <div key={i} style={{
                      background: 'var(--bg-dark)', borderRadius: '10px',
                      padding: '12px 14px', border: '1px solid var(--border)',
                    }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '6px' }}>
                        <span style={{
                          fontSize: '12px', color: 'var(--text-primary)', fontFamily: 'monospace',
                          fontWeight: 600, maxWidth: '280px', overflow: 'hidden',
                          textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                        }} title={ep.endpoint}>
                          {ep.endpoint}
                        </span>
                        <span style={{ fontSize: '13px', fontWeight: 800, color, marginLeft: '8px', flexShrink: 0 }}>
                          {ep.count.toLocaleString()} <span style={{ color: 'var(--text-secondary)', fontWeight: 500, fontSize: '11px' }}>req</span>
                        </span>
                      </div>
                      {/* Progress bar */}
                      <div style={{ height: '4px', background: 'var(--bg-card)', borderRadius: '4px', overflow: 'hidden' }}>
                        <div style={{
                          height: '100%', width: `${pct}%`,
                          background: color, borderRadius: '4px',
                          transition: 'width 0.4s ease',
                        }} />
                      </div>
                      <div style={{ fontSize: '10px', color: 'var(--text-secondary)', marginTop: '3px', textAlign: 'right' }}>
                        {pct}%
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}

export default function Dashboard() {
  const { data, loading, error, refetch } = useApi('/admin/dashboard');
  const [selectedApi, setSelectedApi] = useState(null);
  const [isRefreshing, setIsRefreshing] = useState(false);

  const handleRefresh = () => {
    setIsRefreshing(true);
    refetch();
    setTimeout(() => setIsRefreshing(false), 800);
  };

  if (loading) {
    return (
      <div style={{ textAlign: 'center', padding: '50px', color: 'var(--text-secondary)' }}>
        <span style={{ fontSize: '18px' }}>Scanning systems... Loading dashboard data...</span>
      </div>
    );
  }

  if (error) {
    return (
      <div className="login-error" style={{ margin: '20px' }}>
        Failed to fetch dashboard metrics: {error}
      </div>
    );
  }

  const {
    explorers_count,
    attractions_count,
    pending_approvals_count,
    monthly_revenue,
    growth_data,
    recent_activity,
    api_usage
  } = data;

  const dummy_growth_data = [120, 180, 250, 310, 450, 600, 850, 1200, 1500, 1900, 2400, 3100];
  const display_growth_data = dummy_growth_data;
  const maxVal = Math.max(...display_growth_data, 1);

  return (
    <div className="approvals-modern-container">
      {/* Breakdown Modal */}
      {selectedApi && (
        <BreakdownModal
          api={selectedApi}
          color={selectedApi.color}
          onClose={() => setSelectedApi(null)}
        />
      )}

      {/* Premium Hero Banner */}
      <div className="approvals-hero" style={{
        background: 'linear-gradient(135deg, var(--accent) 0%, var(--accent-2) 100%)',
        borderRadius: '16px',
        padding: '20px 24px',
        color: 'white',
        marginBottom: '24px',
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        boxShadow: '0 8px 24px rgba(0, 122, 124, 0.12)'
      }}>
        <div>
          <h2 style={{ fontSize: '24px', fontWeight: 800, margin: 0, letterSpacing: '-0.5px' }}>Welcome back, Admin!</h2>
          <p style={{ margin: '6px 0 0 0', opacity: 0.9, fontSize: '14px', fontWeight: 500 }}>
            Here is what's happening with NexARound today.
          </p>
        </div>
        <div style={{ display: 'flex', gap: '12px' }}>
          <div style={{ background: 'rgba(255,255,255,0.15)', padding: '10px 16px', borderRadius: '12px', display: 'flex', flexDirection: 'column', alignItems: 'flex-end' }}>
            <span style={{ fontSize: '11px', opacity: 0.8, textTransform: 'uppercase', letterSpacing: '1px', fontWeight: 700 }}>System Status</span>
            <span style={{ fontSize: '14px', fontWeight: 800, display: 'flex', alignItems: 'center', gap: '6px' }}>
              <div style={{ width: '8px', height: '8px', borderRadius: '50%', background: '#4CAF50', boxShadow: '0 0 8px #4CAF50' }}></div>
              All Systems Operational
            </span>
          </div>
        </div>
      </div>

      {/* Stats */}
      <div className="stats-grid">
        <div className="stat-card">
          <div className="stat-icon">
            <CompassIcon size={24} style={{ color: 'var(--accent)' }} />
          </div>
          <div className="stat-value">{explorers_count.toLocaleString()}</div>
          <div className="stat-label">Total Explorers</div>
          <span className="stat-change up" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
            <TrendingUpIcon size={12} /> Active Members
          </span>
        </div>
        <div className="stat-card">
          <div className="stat-icon">
            <MapPinIcon size={24} style={{ color: 'var(--accent)' }} />
          </div>
          <div className="stat-value">{attractions_count.toLocaleString()}</div>
          <div className="stat-label">Total Attractions</div>
          <span className="stat-change up" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
            <TrendingUpIcon size={12} /> Database Records
          </span>
        </div>
        <div className="stat-card">
          <div className="stat-icon">
            <CreditCardIcon size={24} style={{ color: 'var(--accent)' }} />
          </div>
          <div className="stat-value">${monthly_revenue.toLocaleString()}</div>
          <div className="stat-label">Monthly Revenue</div>
          <span className="stat-change up" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
            <TrendingUpIcon size={12} /> Estimated MRR
          </span>
        </div>
        <div className="stat-card">
          <div className="stat-icon">
            <ClockIcon size={24} style={{ color: pending_approvals_count > 0 ? 'var(--warning)' : 'var(--accent)' }} />
          </div>
          <div className="stat-value">{pending_approvals_count}</div>
          <div className="stat-label">Pending Approvals</div>
          <span className={pending_approvals_count > 0 ? "stat-change down" : "stat-change up"} style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
            {pending_approvals_count > 0 ? (
              <><TrendingDownIcon size={12} /> Needs review</>
            ) : (
              <><TrendingUpIcon size={12} /> All cleared</>
            )}
          </span>
        </div>
      </div>

      {/* API Monitoring & Usage */}
      <div className="card" style={{ marginBottom: '24px' }}>
        <div className="card-header" style={{ marginBottom: '16px', paddingBottom: '12px', borderBottom: '1px solid var(--border)' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '2px' }}>
            <div className="card-title">API Usage &amp; Monitoring</div>
            <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
              Click Google Maps chart for endpoint breakdown
            </div>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <span className="badge badge-green">Live Tracking</span>
            <button
              id="dashboard-refresh-btn"
              onClick={handleRefresh}
              title="Refresh all charts"
              style={{
                background: isRefreshing ? 'var(--accent)' : 'var(--bg-dark)',
                border: `1px solid ${isRefreshing ? 'var(--accent)' : 'var(--border)'}`,
                borderRadius: '50px', padding: '7px 16px', cursor: 'pointer',
                color: isRefreshing ? '#fff' : 'var(--text-primary)',
                fontSize: '12px', fontWeight: 700,
                display: 'flex', alignItems: 'center', gap: '7px',
                transition: 'all 0.25s', boxShadow: isRefreshing ? '0 0 12px var(--accent)44' : 'none',
                letterSpacing: '0.2px',
              }}
            >
              <svg
                width="14" height="14" viewBox="0 0 24 24" fill="none"
                stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"
                style={{
                  transform: isRefreshing ? 'rotate(360deg)' : 'none',
                  transition: 'transform 0.7s cubic-bezier(0.4,0,0.2,1)',
                }}
              >
                <polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 .49-3.61"/>
              </svg>
              {isRefreshing ? 'Refreshing…' : 'Refresh'}
            </button>
          </div>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '20px' }}>
          {(api_usage || []).map(api => {
            const maxVal = Math.max(...api.data, 1);
            const isGoogleMaps = api.name === 'Google Maps API';
            return (
              <div
                key={api.name}
                id={`api-chart-${api.name.replace(/\s+/g, '-').toLowerCase()}`}
                onClick={isGoogleMaps ? () => setSelectedApi(api) : undefined}
                style={{
                  background: 'var(--bg-dark)', padding: '16px', borderRadius: '12px',
                  border: '1px solid var(--border)',
                  cursor: isGoogleMaps ? 'pointer' : 'default',
                  transition: 'all 0.2s', position: 'relative', overflow: 'hidden',
                }}
                onMouseEnter={isGoogleMaps ? e => {
                  e.currentTarget.style.border = `1px solid ${api.color}66`;
                  e.currentTarget.style.boxShadow = `0 4px 20px ${api.color}22`;
                  e.currentTarget.style.transform = 'translateY(-2px)';
                } : undefined}
                onMouseLeave={isGoogleMaps ? e => {
                  e.currentTarget.style.border = '1px solid var(--border)';
                  e.currentTarget.style.boxShadow = 'none';
                  e.currentTarget.style.transform = 'none';
                } : undefined}
              >
                {/* Clickable hint — Google Maps only */}
                {isGoogleMaps && (
                  <div style={{
                    position: 'absolute', top: '8px', right: '10px',
                    fontSize: '9px', color: api.color, fontWeight: 700,
                    textTransform: 'uppercase', letterSpacing: '0.5px', opacity: 0.7,
                  }}>
                    Click for details
                  </div>
                )}
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '16px' }}>
                  <span style={{ fontWeight: 700, fontSize: '13px', color: 'var(--text-primary)' }}>{api.name}</span>
                  <span style={{ fontSize: '12px', color: api.color, fontWeight: 700 }}>{api.total} req</span>
                </div>
                <div style={{ position: 'relative', height: '60px', marginTop: '20px', marginBottom: '10px' }}>
                  <svg style={{ width: '100%', height: '100%', overflow: 'visible' }}>
                    {/* Area fill under the line */}
                    <defs>
                      <linearGradient id={`grad-${api.name}`} x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor={api.color} stopOpacity="0.15" />
                        <stop offset="100%" stopColor={api.color} stopOpacity="0" />
                      </linearGradient>
                    </defs>
                    {api.data.map((val, i) => {
                      if (i === api.data.length - 1) return null;
                      const nextVal = api.data[i + 1];
                      const x1 = `${(i / 6) * 100}%`;
                      const y1 = `${100 - (val / maxVal) * 90}%`;
                      const x2 = `${((i + 1) / 6) * 100}%`;
                      const y2 = `${100 - (nextVal / maxVal) * 90}%`;
                      return <line key={`line-${i}`} x1={x1} y1={y1} x2={x2} y2={y2} stroke={api.color} strokeWidth="2" strokeLinecap="round" />;
                    })}
                    {api.data.map((val, i) => {
                      const x = `${(i / 6) * 100}%`;
                      const y = `${100 - (val / maxVal) * 90}%`;
                      return (
                        <circle key={`point-${i}`} cx={x} cy={y} r="4" fill="var(--bg-dark)" stroke={api.color} strokeWidth="2">
                          <title>{val} requests</title>
                        </circle>
                      );
                    })}
                  </svg>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', padding: '0 2px' }}>
                  {['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'].map((day, i) => (
                    <span key={i} style={{ fontSize: '9px', color: 'var(--text-secondary)' }}>{day}</span>
                  ))}
                </div>
              </div>
            );
          })}
        </div>
      </div>

      <div className="two-col">
        {/* Growth Chart */}
        <div className="card">
          <div className="card-header">
            <div className="card-title">Explorer Growth</div>
            <span className="badge badge-blue">Last 12 Months</span>
          </div>
          <div className="chart-wrap">
            {display_growth_data.map((val, i) => (
              <div className="chart-bar-col" key={i}>
                <div className="chart-bar" style={{ height: `${(val / maxVal) * 100}%` }} title={`${val} signups`} />
                <span className="chart-label">{MONTHS[i]}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Recent Activity */}
        <div className="card">
          <div className="card-header">
            <div className="card-title">Recent Activity</div>
          </div>
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
        </div>
      </div>
    </div>
  );
}
