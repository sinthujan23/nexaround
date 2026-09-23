import { useApi } from '../api';
import { TicketIcon, InboxIcon, ClockIcon, CheckIcon } from '../components/Icons';

const COLOMBO = { timeZone: 'Asia/Colombo', dateStyle: 'medium', timeStyle: 'short' };

export default function Dashboard({ onNavigate }) {
  const { data: stats, loading } = useApi('/partner/stats');
  const { data: recent } = useApi('/partner/enquiries?page=1&page_size=5');

  const tiles = [
    { label: 'Packages live', value: stats?.packages_published ?? 0, Icon: CheckIcon,
      sub: `${stats?.packages_total ?? 0} in total` },
    { label: 'New enquiries', value: stats?.enquiries_new ?? 0, Icon: InboxIcon,
      sub: 'waiting for a reply' },
    { label: 'Last 30 days', value: stats?.enquiries_last_30d ?? 0, Icon: ClockIcon,
      sub: 'enquiries received' },
    { label: 'All enquiries', value: stats?.enquiries_total ?? 0, Icon: TicketIcon,
      sub: 'since you joined' },
  ];

  return (
    <>
      {loading && <div className="loader" />}

      <div className="stats-grid">
        {tiles.map(({ label, value, sub, Icon }) => (
          <div key={label} className="stat-card">
            <div className="stat-icon"><Icon size={20} /></div>
            <div className="stat-value">{value}</div>
            <div className="stat-label">{label}</div>
            <div className="stat-change">{sub}</div>
          </div>
        ))}
      </div>

      <div className="card" style={{ padding: '24px', marginTop: '20px' }}>
        <div className="card-header">
          <div className="card-title">Latest enquiries</div>
          <button className="btn btn-ghost" onClick={() => onNavigate('enquiries')}>
            See all
          </button>
        </div>

        {(!recent || recent.enquiries.length === 0) && (
          <div className="empty-state">
            <InboxIcon size={32} className="empty-icon" />
            <div>No enquiries yet. They arrive here when a traveller asks about a package.</div>
          </div>
        )}

        {recent && recent.enquiries.length > 0 && (
          <div className="modern-list">
            {recent.enquiries.map((e) => (
              <div key={e.id} className="modern-list-item">
                <div style={{ flex: 1 }}>
                  <div style={{ fontWeight: 600 }}>{e.contact_name}</div>
                  <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                    {e.package_title_snapshot || 'General enquiry'}
                    {' · '}
                    {e.created_at ? new Date(e.created_at).toLocaleString('en-GB', COLOMBO) : ''}
                  </div>
                </div>
                <span className={`badge ${e.status === 'new' ? 'badge-yellow'
                  : e.status === 'contacted' ? 'badge-green' : 'badge-ghost'}`}>
                  {e.status}
                </span>
              </div>
            ))}
          </div>
        )}
      </div>
    </>
  );
}
