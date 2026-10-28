import { useEffect, useRef } from 'react';
import { Outlet, useLocation, useNavigate } from 'react-router-dom';
import { NAV_ITEMS } from '../../nav';
import { isCreator } from '../../session';
import { useEnquiryAlerts } from '../../enquiryAlerts';
import { CrossIcon, InboxIcon } from '../Icons';
import ErrorBoundary from '../ErrorBoundary';
import Sidebar from './Sidebar';
import PageHeader from './PageHeader';

/** One pop-up: a new request or a vendor's answer. Goes after 20 seconds. */
function EnquiryPopup({ event, onOpen, onClose }) {
  // The layout re-renders on every poll; the 20 seconds must not restart.
  const close = useRef(onClose);
  close.current = onClose;
  useEffect(() => {
    const timer = setTimeout(() => close.current(), 20000);
    return () => clearTimeout(timer);
  }, []);
  return (
    <div className={`enquiry-popup kind-${event.kind}`} role="status">
      <span className="enquiry-popup-icon"><InboxIcon size={16} /></span>
      <button type="button" className="enquiry-popup-main" onClick={onOpen}>
        <strong>{event.title}</strong>
        {event.body && <span>{event.body}</span>}
      </button>
      <button type="button" className="enquiry-popup-close" title="Dismiss" onClick={onClose}>
        <CrossIcon size={14} />
      </button>
    </div>
  );
}

function Main() {
  const { pathname } = useLocation();
  const page = NAV_ITEMS.find((item) => item.path === pathname);
  return (
    <main className="main-content">
      <PageHeader title={page?.title} />
      <div className="page-body">
        {/* Keyed on the path so a page that crashed recovers once you navigate away. */}
        <ErrorBoundary key={pathname}>
          <Outlet />
        </ErrorBoundary>
      </div>
    </main>
  );
}

function AdminChrome({ onLogout }) {
  const navigate = useNavigate();
  const alerts = useEnquiryAlerts();

  return (
    <div className="admin-layout">
      <Sidebar onLogout={onLogout} extraCounts={{ enquiries: alerts.open }} />
      <div className="enquiry-popups">
        {alerts.popups.map((ev) => (
          <EnquiryPopup
            key={`${ev.kind}-${ev.id}`}
            event={ev}
            onOpen={() => { alerts.dismiss(ev); navigate(`/enquiries?id=${ev.id}`); }}
            onClose={() => alerts.dismiss(ev)}
          />
        ))}
      </div>
      <Main />
    </div>
  );
}

/** A content creator's panel: City Tours only, so no enquiry alerts either. */
export default function AdminLayout({ onLogout }) {
  if (isCreator()) {
    return (
      <div className="admin-layout">
        <Sidebar onLogout={onLogout} />
        <Main />
      </div>
    );
  }
  return <AdminChrome onLogout={onLogout} />;
}
