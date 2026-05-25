import { useApi } from '../api';
import { DollarIcon, UsersIcon, TrendingDownIcon, TrendingUpIcon, RefreshIcon } from '../components/Icons';

export default function Payments() {
  const { data, loading, error } = useApi('/admin/payments');

  if (loading) {
    return (
      <div style={{ textAlign: 'center', padding: '50px', color: 'var(--text-secondary)' }}>
        <span style={{ fontSize: '18px' }}>Accessing ledger... Loading financial metrics...</span>
      </div>
    );
  }

  if (error) {
    return (
      <div className="login-error" style={{ margin: '20px' }}>
        Failed to fetch payment details: {error}
      </div>
    );
  }

  const { mrr, subscribers_count, churn_rate, arpu, plans, transactions } = data;
  
  // Calculate total users across all plans for progress bar scale
  const totalUsers = plans.reduce((acc, p) => acc + p.users, 0) || 1;

  return (
    <div>
      <div className="stats-grid">
        <div className="stat-card">
          <div className="stat-icon">
            <DollarIcon size={24} style={{ color: 'var(--accent)' }} />
          </div>
          <div className="stat-value">${mrr.toLocaleString()}</div>
          <div className="stat-label">Monthly Revenue (MRR)</div>
          <span className="stat-change up" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
            <TrendingUpIcon size={12} /> 5.2% vs last month
          </span>
        </div>
        <div className="stat-card">
          <div className="stat-icon">
            <UsersIcon size={24} style={{ color: 'var(--accent)' }} />
          </div>
          <div className="stat-value">{subscribers_count.toLocaleString()}</div>
          <div className="stat-label">Active Subscribers</div>
          <span className="stat-change up" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
            <TrendingUpIcon size={12} /> Pro & Annual users
          </span>
        </div>
        <div className="stat-card">
          <div className="stat-icon">
            <TrendingDownIcon size={24} style={{ color: 'var(--danger)' }} />
          </div>
          <div className="stat-value">{churn_rate}</div>
          <div className="stat-label">Churn Rate</div>
          <span className="stat-change up" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
            <TrendingDownIcon size={12} /> Stable retention
          </span>
        </div>
        <div className="stat-card">
          <div className="stat-icon">
            <RefreshIcon size={24} style={{ color: 'var(--accent)' }} />
          </div>
          <div className="stat-value">{arpu}</div>
          <div className="stat-label">Avg Revenue Per User</div>
          <span className="stat-change up" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
            <TrendingUpIcon size={12} /> Active ARPU
          </span>
        </div>
      </div>

      <div className="two-col">
        {/* Subscription Plans */}
        <div className="card">
          <div className="card-header">
            <div className="card-title">Subscription Plans</div>
          </div>
          {plans.map(p => (
            <div key={p.name} style={{ marginBottom: '16px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '6px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <div style={{ width: '10px', height: '10px', borderRadius: '50%', background: p.color }} />
                  <span style={{ fontSize: '13px', fontWeight: 600, color: 'var(--text-primary)' }}>{p.name}</span>
                  <span style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>{p.price}</span>
                </div>
                <span style={{ fontSize: '13px', fontWeight: 700, color: 'var(--text-primary)' }}>{p.users.toLocaleString()} users</span>
              </div>
              <div style={{ height: '6px', background: 'rgba(255,255,255,0.05)', borderRadius: '4px', overflow: 'hidden' }}>
                <div style={{ height: '100%', width: `${(p.users / totalUsers) * 100}%`, background: p.color, borderRadius: '4px', transition: 'width 0.8s ease' }} />
              </div>
            </div>
          ))}
        </div>

        {/* Revenue MRR Chart */}
        <div className="card">
          <div className="card-header">
            <div className="card-title">Revenue Trend</div>
            <span className="badge badge-green">+5.2%</span>
          </div>
          <div className="chart-wrap">
            {[2800, 3200, 3500, 3800, 4100, mrr].map((v, i) => (
              <div className="chart-bar-col" key={i}>
                <div className="chart-bar" style={{ height: `${(v / mrr) * 100}%`, background: 'linear-gradient(180deg, var(--accent), var(--accent-2))' }} />
                <span className="chart-label">{['Dec','Jan','Feb','Mar','Apr','May'][i]}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Transactions */}
      <div className="card">
        <div className="card-header">
          <div className="card-title">Recent Transactions</div>
          <button className="btn btn-ghost" style={{ fontSize: '12px', padding: '6px 12px' }} onClick={() => alert('Exporting transaction logs...')}>Export CSV</button>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Transaction ID</th>
                <th>User</th>
                <th>Plan</th>
                <th>Amount</th>
                <th>Date</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {transactions.map(t => (
                <tr key={t.id}>
                  <td style={{ fontFamily: 'monospace', fontSize: '12px', color: 'var(--text-secondary)' }}>{t.id}</td>
                  <td>
                    <div className="user-info">
                      <div className="user-avatar">{t.user[0]}</div>
                      <span style={{ fontSize: '13px', fontWeight: 500, color: 'var(--text-primary)' }}>{t.user}</span>
                    </div>
                  </td>
                  <td><span className="badge badge-blue">{t.plan}</span></td>
                  <td style={{ fontWeight: 700, color: 'var(--text-primary)' }}>${t.amount.toFixed(2)}</td>
                  <td style={{ color: 'var(--text-secondary)', fontSize: '12px' }}>{t.date}</td>
                  <td>
                    <span className={`badge ${
                      t.status === 'Completed' ? 'badge-green' :
                      t.status === 'Failed' ? 'badge-red' : 'badge-yellow'
                    }`}>{t.status}</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
