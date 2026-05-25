export default function Engagement() {
  return (
    <div className="page-body">
      <div className="card mt-4">
        <div className="card-header">
          <div className="card-title">User Engagement Metrics</div>
        </div>
        <div className="stats-grid">
          <div className="stat-card">
            <div className="stat-label">Daily Active Users</div>
            <div className="stat-value">845</div>
            <div className="stat-change up">+5.1% vs last week</div>
          </div>
          <div className="stat-card">
            <div className="stat-label">Avg Session Length</div>
            <div className="stat-value">4m 20s</div>
            <div className="stat-change up">+12s vs last week</div>
          </div>
          <div className="stat-card">
            <div className="stat-label">Places Visited</div>
            <div className="stat-value">12,450</div>
            <div className="stat-change up">+8.2% vs last month</div>
          </div>
        </div>
      </div>
    </div>
  );
}
