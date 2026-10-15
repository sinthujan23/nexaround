import { Outlet } from 'react-router-dom';
import TabNav from '../../components/TabNav';

const TABS = [
  { to: '/security', label: 'Devices', end: true },
  { to: '/security/activity', label: 'Account activity' },
];

export default function SecurityLayout() {
  return (
    <div>
      <TabNav items={TABS} className="page-level" />
      <Outlet />
    </div>
  );
}
