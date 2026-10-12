import { Outlet, useLocation } from 'react-router-dom';
import { NAV_ITEMS } from '../../nav';
import ErrorBoundary from '../ErrorBoundary';
import Sidebar from './Sidebar';
import PageHeader from './PageHeader';

export default function AdminLayout({ onLogout }) {
  const { pathname } = useLocation();
  const page = NAV_ITEMS.find((item) => item.path === pathname);

  return (
    <div className="admin-layout">
      <Sidebar onLogout={onLogout} />
      <main className="main-content">
        <PageHeader title={page?.title} />
        <div className="page-body">
          {/* Keyed on the path so a page that crashed recovers once you navigate away. */}
          <ErrorBoundary key={pathname}>
            <Outlet />
          </ErrorBoundary>
        </div>
      </main>
    </div>
  );
}
