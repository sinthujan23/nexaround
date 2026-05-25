export default function Users() {
  return (
    <div className="page-body">
      <div className="card mt-4">
        <div className="card-header">
          <div className="card-title">User Management</div>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Name</th>
                <th>Email</th>
                <th>Role</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Alex Smith</td>
                <td>alex@example.com</td>
                <td>Pro Explorer</td>
                <td><span className="badge badge-green">Active</span></td>
                <td><button className="action-btn">Edit</button></td>
              </tr>
              <tr>
                <td>Sarah Jones</td>
                <td>sarah@example.com</td>
                <td>Explorer</td>
                <td><span className="badge badge-yellow">Pending</span></td>
                <td><button className="action-btn">Edit</button></td>
              </tr>
              <tr>
                <td>Mike Brown</td>
                <td>mike@example.com</td>
                <td>Creator</td>
                <td><span className="badge badge-green">Active</span></td>
                <td><button className="action-btn">Edit</button></td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
