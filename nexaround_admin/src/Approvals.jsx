export default function Approvals() {
  return (
    <div className="page-body">
      <div className="card mt-4">
        <div className="card-header">
          <div className="card-title">Place Approvals</div>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Place Name</th>
                <th>Submitted By</th>
                <th>Category</th>
                <th>Date</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Central Park Coffee</td>
                <td>Sarah Jones</td>
                <td>Cafe</td>
                <td>Today, 10:00 AM</td>
                <td>
                  <button className="action-btn approve">Approve</button>
                  <button className="action-btn reject" style={{marginLeft: "8px"}}>Reject</button>
                </td>
              </tr>
              <tr>
                <td>Grand Theater</td>
                <td>Alex Smith</td>
                <td>Entertainment</td>
                <td>Yesterday</td>
                <td>
                  <button className="action-btn approve">Approve</button>
                  <button className="action-btn reject" style={{marginLeft: "8px"}}>Reject</button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
