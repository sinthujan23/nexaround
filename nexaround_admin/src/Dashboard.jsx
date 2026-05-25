export default function Dashboard() {
  const stats = {
    explorers: 1420,
    attractions: 350,
    revenue: 4520,
    growth: '+12.5%'
  };

  return (
    <div className="page-body">
      <div className="stats-grid">
        <div className="stat-card">
          <div className="stat-label">Total Explorers</div>
          <div className="stat-value">{stats.explorers.toLocaleString()}</div>
          <div className="stat-change up">{stats.growth} this month</div>
        </div>
        
        <div className="stat-card">
          <div className="stat-label">Total Attractions</div>
          <div className="stat-value">{stats.attractions.toLocaleString()}</div>
          <div className="stat-change up">+8 this week</div>
        </div>
        
        <div className="stat-card">
          <div className="stat-label">Monthly Revenue</div>
          <div className="stat-value">${stats.revenue.toLocaleString()}</div>
          <div className="stat-change up">+5.2% this month</div>
        </div>
      </div>

      <div className="card mt-4">
        <div className="card-header">
          <div className="card-title">Recent Activity</div>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>User</th>
                <th>Action</th>
                <th>Time</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Alex Smith</td>
                <td>Signed up for Pro Explorer</td>
                <td>2 mins ago</td>
                <td><span className="badge badge-green">Completed</span></td>
              </tr>
              <tr>
                <td>Sarah Jones</td>
                <td>Suggested a new place</td>
                <td>15 mins ago</td>
                <td><span className="badge badge-yellow">Pending</span></td>
              </tr>
              <tr>
                <td>Mike Brown</td>
                <td>Account verified</td>
                <td>1 hour ago</td>
                <td><span className="badge badge-green">Success</span></td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
