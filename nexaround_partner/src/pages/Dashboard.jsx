import { Link } from 'react-router-dom';
import { useApi, mediaUrl } from '../api';
import { useAuth } from '../auth';
import { RESYNC, useLiveEvent } from '../live';
import { TicketIcon, CheckIcon, PlusIcon, EditIcon, InboxIcon } from '../components/Icons';
import { EmptyState, ListRow, Loader, StatusPill } from '../components/Lists';
import { formatPrice, basisLabel, reviewState, visibility, visibilityTone } from '../format';

// The dashboard shows the first few; the rest are one click away.
const PACKAGE_PREVIEW = 5;

export default function Dashboard() {
  const { me } = useAuth();
  const { data: stats, refetch: refetchStats } = useApi('/partner/stats');
  const { data: packageData, refetch: refetchPackages } = useApi('/partner/packages');

  // Requests show as a count only: package, date and guests are on Requests.
  useLiveEvent(['packages.changed', 'account.changed', 'requests.changed', RESYNC], () => {
    refetchStats();
    refetchPackages();
  });
  const packages = packageData?.packages || [];

  const tiles = [
    { label: 'Requests to answer', value: stats?.requests_waiting, Icon: InboxIcon,
      sub: 'Confirm or offer another date', to: '/requests', warm: (stats?.requests_waiting || 0) > 0 },
    { label: 'Packages live', value: stats?.packages_published, Icon: CheckIcon,
      sub: `${stats?.packages_total ?? 0} in total`, to: '/packages' },
  ];

  const vendorName = me?.vendor_name || 'Partner';

  return (
    <>
      <div className="dash-top">
        <div className="dash-greeting">
          <h1 className="dash-title">Welcome back, {vendorName}</h1>
          {/* A hidden listing already gets the red banner above the page. */}
          {me?.vendor_is_active && (
            <p className="dash-sub"><span className="live-dot" /> Your listing is live on nexARound</p>
          )}
        </div>
        <div className="dash-actions">
          <Link className="btn btn-ghost" to="/profile">
            <EditIcon size={15} /> Profile
          </Link>
          <Link className="btn btn-primary" to="/packages/new">
            <PlusIcon size={15} /> New package
          </Link>
        </div>
      </div>

      <div className="kpi-grid">
        {tiles.map(({ label, value, sub, Icon, to, warm }) => (
          <Link key={label} to={to} className={`kpi ${warm ? 'warm' : ''}`}>
            <span className="kpi-label"><Icon size={16} /> {label}</span>
            <span className="kpi-value">{value ?? '–'}</span>
            <span className="kpi-sub">{sub}</span>
          </Link>
        ))}
      </div>

      <div className="dash-cols single">
        <section className="panel">
          <div className="panel-head">
            <span className="panel-title">Your packages</span>
            <Link className="link-btn" to="/packages">Manage</Link>
          </div>

          {!packageData && <div className="panel-pad"><Loader /></div>}

          {packageData && packages.length === 0 && (
            <EmptyState
              icon={TicketIcon} title="List your first package" pad={40}
              action={(
                <Link className="btn btn-primary btn-sm" to="/packages/new">
                  <PlusIcon size={15} /> Add package
                </Link>
              )}
            >
              Each package appears in the app as its own experience travellers can enquire about.
            </EmptyState>
          )}

          {packages.slice(0, PACKAGE_PREVIEW).map((pkg) => (
            <ListRow
              key={pkg.id}
              to={`/packages/${pkg.id}`}
              lead={(
                <span className="dash-thumb">
                  {pkg.photo_urls?.[0] ? <img src={mediaUrl(pkg.photo_urls[0])} alt="" /> : <TicketIcon size={18} />}
                </span>
              )}
              title={pkg.title}
              subs={[formatPrice(pkg), pkg.price_amount != null && basisLabel(pkg.price_basis)].filter(Boolean).join(' · ')}
              side={(
                <>
                  {reviewState(pkg) && <StatusPill tone={reviewState(pkg).tone}>{reviewState(pkg).label}</StatusPill>}
                  <StatusPill tone={visibilityTone(pkg)}>{visibility(pkg)}</StatusPill>
                </>
              )}
            />
          ))}
        </section>
      </div>
    </>
  );
}
