export default function Payments() {
  return (
    <div className="page-body">
      <div className="card mt-4">
        <div className="card-header">
          <div className="card-title">Payments & Plans</div>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>User</th>
                <th>Plan</th>
                <th>Amount</th>
                <th>Date</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Alex Smith</td>
                <td>Pro Explorer</td>
                <td>$9.99</td>
                <td>Oct 24, 2023</td>
                <td><span className="badge badge-green">Paid</span></td>
              </tr>
              <tr>
                <td>Mike Brown</td>
                <td>Creator Pro</td>
                <td>$29.99</td>
                <td>Oct 23, 2023</td>
                <td><span className="badge badge-green">Paid</span></td>
              </tr>
              <tr>
                <td>Sarah Jones</td>
                <td>Pro Explorer</td>
                <td>$9.99</td>
                <td>Oct 22, 2023</td>
                <td><span className="badge badge-red">Failed</span></td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
