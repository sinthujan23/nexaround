import { Fragment } from 'react';
import { NavLink } from 'react-router-dom';
import { navSectionsFor } from '../../nav';
import { compactCount, usePlaceCounts } from '../../places';
import { useVendorChangeCount } from '../../vendorChanges';
import { useProviderApplicationCount } from '../../providerApplications';
import { useCityTourCount } from '../../cityTours';
import { ADMIN, CREATOR, isCreator, sessionName } from '../../session';
import { LogOutIcon } from '../Icons';

/** The admin's sidebar, with the live counts its badges show. */
function AdminSidebar({ onLogout, extraCounts }) {
  const placeCounts = usePlaceCounts();
  const vendorChanges = useVendorChangeCount();
  const applications = useProviderApplicationCount();
  const cityTours = useCityTourCount();
  const counts = {
    ...placeCounts, vendor_changes: vendorChanges, provider_applications: applications,
    city_tours: cityTours, ...extraCounts,
  };
  return (
    <SidebarView
      onLogout={onLogout} sections={navSectionsFor(ADMIN)} counts={counts}
      user={{ name: 'Admin', role: 'Administrator' }}
    />
  );
}

/**
 * A content creator sees City Tours only, and no counts: those come from
 * admin endpoints, which refuse a creator's token (and a refusal signs out).
 */
export default function Sidebar(props) {
  if (isCreator()) {
    return (
      <SidebarView
        onLogout={props.onLogout} sections={navSectionsFor(CREATOR)} counts={{}} creator
        user={{ name: sessionName(), role: 'Content creator' }}
      />
    );
  }
  return <AdminSidebar {...props} />;
}

function SidebarView({ onLogout, sections, counts, user, creator = false }) {
  return (
    <aside className="sidebar">
      <div className="sidebar-logo">
        <span className="logo-tile">
          <img
            src="/logo_2.png"
            alt="nexARound"
            onError={(e) => { e.currentTarget.style.display = 'none'; }}
          />
        </span>
        <div>
          <div className="brand">nexARound</div>
          <div className="brand-sub">ADMIN PORTAL</div>
        </div>
      </div>
      <nav className="sidebar-nav">
        {sections.map((section, i) => (
          <Fragment key={section.label}>
            <div className="nav-section-label" style={i > 0 ? { marginTop: '8px' } : undefined}>
              {section.label}
            </div>
            {section.items.map(({ path, label, creatorLabel, icon: Icon, badge }) => (
              // `end`, or /places would also light up on /places/review.
              <NavLink key={path} to={path} end className="nav-item">
                <span className="icon"><Icon size={18} /></span> {(creator && creatorLabel) || label}
                {badge && counts[badge] > 0 && (
                  <span className="nav-badge" title={`${counts[badge].toLocaleString()} waiting`}>
                    {compactCount(counts[badge])}
                  </span>
                )}
              </NavLink>
            ))}
          </Fragment>
        ))}
      </nav>
      <div className="sidebar-footer">
        <div className="admin-user">
          <div className="admin-avatar">{(user.name || 'A').charAt(0).toUpperCase()}</div>
          <div className="user-info" style={{ display: 'flex', flexDirection: 'column', minWidth: 0, flex: 1, gap: '2px' }}>
            <div className="admin-name" title={user.name}>{user.name}</div>
            <div className="admin-role" title={user.role}>{user.role}</div>
          </div>
        </div>
        <button className="logout-btn" title="Sign out" onClick={onLogout}>
          <LogOutIcon size={16} />
        </button>
      </div>
    </aside>
  );
}
