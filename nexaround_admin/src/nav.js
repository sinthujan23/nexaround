import Dashboard from './pages/Dashboard';
import Users from './pages/Users';
import Approvals from './pages/Approvals';
import Payments from './pages/Payments';
import Engagement from './pages/Engagement';
import Attractions from './pages/Attractions';
import ExcludeKeywords from './pages/ExcludeKeywords';
import Media from './pages/Media';
import Settings from './pages/Settings';
import ApiUsage from './pages/ApiUsage';
import Experiences from './pages/Experiences';
import ExperienceEnquiries from './pages/ExperienceEnquiries';
import {
  CompassIcon, UsersIcon, MapPinIcon, CreditCardIcon, MegaphoneIcon, ImageIcon, SettingsIcon,
  ClipboardCheckIcon, TrendingUpIcon, EyeOffIcon, TicketIcon, InboxIcon,
} from './components/Icons';

/**
 * Every admin page, in sidebar order. The sidebar, the header title and the
 * routes are all built from this one list — adding a page is one entry here.
 */
export const NAV_SECTIONS = [
  {
    label: 'Main Menu',
    items: [
      { path: '/dashboard', label: 'Dashboard', title: 'Dashboard Overview', icon: CompassIcon, page: Dashboard },
      { path: '/attractions', label: 'Attractions', title: 'Manage Attractions', icon: MapPinIcon, page: Attractions },
      { path: '/approvals', label: 'Place Approvals', title: 'Place Approvals', icon: ClipboardCheckIcon, page: Approvals },
      { path: '/exclude-keywords', label: 'Exclude Keywords', title: 'Exclude Keywords', icon: EyeOffIcon, page: ExcludeKeywords },
      { path: '/media', label: 'Media Library', title: 'Media Library', icon: ImageIcon, page: Media },
    ],
  },
  {
    label: 'Business',
    items: [
      { path: '/experiences', label: 'Experiences', title: 'Experiences & Vendors', icon: TicketIcon, page: Experiences },
      { path: '/enquiries', label: 'Enquiries', title: 'Experience Enquiries', icon: InboxIcon, page: ExperienceEnquiries },
      { path: '/payments', label: 'Payments & Plans', title: 'Payments & Plans', icon: CreditCardIcon, page: Payments },
    ],
  },
  {
    label: 'System',
    items: [
      { path: '/users', label: 'User Management', title: 'Explorer Management', icon: UsersIcon, page: Users },
      { path: '/engagement', label: 'Engagement', title: 'Engagement & Broadcasting', icon: MegaphoneIcon, page: Engagement },
      { path: '/api-usage', label: 'API Usage', title: 'API Usage & Cost', icon: TrendingUpIcon, page: ApiUsage },
      { path: '/settings', label: 'Settings', title: 'General Settings', icon: SettingsIcon, page: Settings },
    ],
  },
];

export const NAV_ITEMS = NAV_SECTIONS.flatMap((section) => section.items);

export const HOME_PATH = '/dashboard';
export const LOGIN_PATH = '/login';
