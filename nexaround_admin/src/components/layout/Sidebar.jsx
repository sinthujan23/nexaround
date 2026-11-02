import { Fragment, useEffect, useState } from 'react';
import { NavLink } from 'react-router-dom';
import { navSectionsFor } from '../../nav';
import { compactCount, usePlaceCounts } from '../../places';
import { useVendorChangeCount } from '../../vendorChanges';
import { useProviderApplicationCount } from '../../providerApplications';
import { useCityTourCount } from '../../cityTours';
import { ADMIN, CREATOR, isCreator, sessionName } from '../../session';
import { CrossIcon, LogOutIcon, MenuIcon } from '../Icons';

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

// The width at which the sidebar becomes a slide-out menu. Keep in step with
// the `max-width: 900px` block in index.css.
const PHONE_NAV = '(max-width: 900px)';

/**
 * On a phone or small tablet the sidebar slides in from the left behind a
 * menu button in the page header; on wider screens it is the fixed rail and
 * the button, scrim and close button are hidden by CSS.
 */
function useMobileNav() {
  const [open, setOpen] = useState(false);
  useEffect(() => {
    if (!open) return undefined;
    // The page behind must not scroll while the menu is over it.
    const previous = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const onKey = (e) => { if (e.key === 'Escape') setOpen(false); };
    // Turning a tablet to landscape (or widening a window) past the rail
    // width shows the fixed sidebar instead, so the menu closes.
    const wide = window.matchMedia(PHONE_NAV);
    const onWide = () => { if (!wide.matches) setOpen(false); };
    window.addEventListener('keydown', onKey);
    wide.addEventListener('change', onWide);
    return () => {
      document.body.style.overflow = previous;
      window.removeEventListener('keydown', onKey);
      wide.removeEventListener('change', onWide);
    };
  }, [open]);
  return [open, setOpen];
}

function SidebarView({ onLogout, sections, counts, user, creator = false }) {
  const [open, setOpen] = useMobileNav();
  const close = () => setOpen(false);
  const waiting = sections.some((s) => s.items.some(({ badge }) => badge && counts[badge] > 0));
  return (
    <>
      <button
        type="button"
        className="mobile-nav-toggle"
        aria-label={waiting ? 'Open menu (items waiting)' : 'Open menu'}
        aria-expanded={open}
        onClick={() => setOpen(true)}
      >
        <MenuIcon size={20} />
        {waiting && <span className="mobile-nav-dot" />}
      </button>
      {open && <div className="sidebar-scrim" onClick={close} aria-hidden="true" />}
      <aside className={`sidebar${open ? ' open' : ''}`}>
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
          <button type="button" className="sidebar-close" aria-label="Close menu" onClick={close}>
            <CrossIcon size={18} />
          </button>
        </div>
        <nav className="sidebar-nav">
          {sections.map((section, i) => (
            <Fragment key={section.label}>
              <div className="nav-section-label" style={i > 0 ? { marginTop: '8px' } : undefined}>
                {section.label}
              </div>
              {section.items.map(({ path, label, creatorLabel, icon: Icon, badge }) => (
                // `end`, or /places would also light up on /places/review.
                <NavLink key={path} to={path} end className="nav-item" onClick={close}>
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
    </>
  );
}
