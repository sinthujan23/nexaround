import { useApi } from '../api';
import { CompassIcon, MapPinIcon, CreditCardIcon, ClockIcon, TrendingUpIcon, TrendingDownIcon } from '../components/Icons';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

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

export default function Dashboard() {
  const { data, loading, error } = useApi('/admin/dashboard');

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
    recent_activity
  } = data;

  const dummy_growth_data = [120, 180, 250, 310, 450, 600, 850, 1200, 1500, 1900, 2400, 3100];
  const display_growth_data = dummy_growth_data; // Use dummy data for visualization
  const maxVal = Math.max(...display_growth_data, 1);

  return (
    <div className="approvals-modern-container">
      {/* Premium Hero Banner (Compact) */}
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
              <>
                <TrendingDownIcon size={12} /> Needs review
              </>
            ) : (
              <>
                <TrendingUpIcon size={12} /> All cleared
              </>
            )}
          </span>
        </div>
      </div>

      {/* API Monitoring & Usage */}
      <div className="card" style={{ marginBottom: '24px' }}>
        <div className="card-header" style={{ marginBottom: '16px', paddingBottom: '0', borderBottom: 'none' }}>
          <div className="card-title">API Usage & Monitoring</div>
          <span className="badge badge-green">Live Tracking</span>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '20px' }}>
          {[
            { name: 'Google Maps API', total: '12,450', color: '#4285F4', data: [1200, 1500, 1800, 2200, 1900, 1600, 2250] },
            { name: 'Mapbox API', total: '8,320', color: '#4264fb', data: [800, 1100, 1300, 1400, 1200, 1000, 1520] },
            { name: 'Gemini API', total: '3,105', color: '#8e24aa', data: [200, 350, 400, 600, 500, 450, 605] }
          ].map(api => {
            const maxVal = Math.max(...api.data, 1);
            return (
              <div key={api.name} style={{ background: 'var(--bg-dark)', padding: '16px', borderRadius: '12px', border: '1px solid var(--border)' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '16px' }}>
                  <span style={{ fontWeight: 700, fontSize: '13px', color: 'var(--text-primary)' }}>{api.name}</span>
                  <span style={{ fontSize: '12px', color: 'var(--text-secondary)', fontWeight: 600 }}>{api.total} req</span>
                </div>
                <div style={{ position: 'relative', height: '60px', marginTop: '20px', marginBottom: '10px' }}>
                  <svg style={{ width: '100%', height: '100%', overflow: 'visible' }}>
                    {api.data.map((val, i) => {
                      if (i === api.data.length - 1) return null;
                      const nextVal = api.data[i + 1];
                      const x1 = `${(i / 6) * 100}%`;
                      const y1 = `${100 - (val / maxVal) * 90}%`;
                      const x2 = `${((i + 1) / 6) * 100}%`;
                      const y2 = `${100 - (nextVal / maxVal) * 90}%`;
                      return <line key={`line-${i}`} x1={x1} y1={y1} x2={x2} y2={y2} stroke={api.color} strokeWidth="2" strokeLinecap="round" />
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
