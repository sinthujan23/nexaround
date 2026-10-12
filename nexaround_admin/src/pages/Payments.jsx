import { useApi } from '../api';
import { DollarIcon, UsersIcon, TrendingDownIcon, TrendingUpIcon, RefreshIcon } from '../components/Icons';
import { Card, StatCard, Badge, PageLoading, PageError } from '../components/Kit';

export default function Payments() {
  const { data, loading, error } = useApi('/admin/payments');

  if (loading) {
    return <PageLoading>Accessing ledger... Loading financial metrics...</PageLoading>;
  }

  if (error) {
    return <PageError>Failed to fetch payment details: {error}</PageError>;
  }

  const { mrr, subscribers_count, churn_rate, arpu, plans, transactions } = data;
  
  // Calculate total users across all plans for progress bar scale
  const totalUsers = plans.reduce((acc, p) => acc + p.users, 0) || 1;

  return (
    <div>
      <div className="stats-grid">
        <StatCard icon={DollarIcon} value={`$${mrr.toLocaleString()}`} label="Monthly Revenue (MRR)"
          changeIcon={TrendingUpIcon} change="5.2% vs last month" />
        <StatCard icon={UsersIcon} value={subscribers_count.toLocaleString()} label="Active Subscribers"
          changeIcon={TrendingUpIcon} change="Pro & Annual users" />
        <StatCard icon={TrendingDownIcon} iconColor="var(--danger)" value={churn_rate} label="Churn Rate"
          changeIcon={TrendingDownIcon} change="Stable retention" />
        <StatCard icon={RefreshIcon} value={arpu} label="Avg Revenue Per User"
          changeIcon={TrendingUpIcon} change="Active ARPU" />
      </div>

      <div className="two-col">
        {/* Subscription Plans */}
        <Card title="Subscription Plans">
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
        </Card>

        {/* Revenue MRR Chart */}
        <Card title="Revenue Trend" action={<Badge tone="green">+5.2%</Badge>}>
          <div className="chart-wrap">
            {[2800, 3200, 3500, 3800, 4100, mrr].map((v, i) => (
              <div className="chart-bar-col" key={i}>
                <div className="chart-bar" style={{ height: `${(v / mrr) * 100}%`, background: 'linear-gradient(180deg, var(--accent), var(--accent-2))' }} />
                <span className="chart-label">{['Dec','Jan','Feb','Mar','Apr','May'][i]}</span>
              </div>
            ))}
          </div>
        </Card>
      </div>

      {/* Transactions */}
      <Card
        title="Recent Transactions"
        action={<button className="btn btn-ghost" style={{ fontSize: '12px', padding: '6px 12px' }} onClick={() => alert('Exporting transaction logs...')}>Export CSV</button>}
      >
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
                  <td><Badge tone="blue">{t.plan}</Badge></td>
                  <td style={{ fontWeight: 700, color: 'var(--text-primary)' }}>${t.amount.toFixed(2)}</td>
                  <td style={{ color: 'var(--text-secondary)', fontSize: '12px' }}>{t.date}</td>
                  <td>
                    <Badge tone={t.status === 'Completed' ? 'green' : t.status === 'Failed' ? 'red' : 'yellow'}>{t.status}</Badge>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  );
}
