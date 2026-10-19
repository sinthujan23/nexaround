import Dashboard from './pages/Dashboard';
import Users from './pages/Users';
import Payments from './pages/Payments';
import Engagement from './pages/Engagement';
import Places from './pages/Places';
import ReviewQueue from './pages/ReviewQueue';
import ExcludeKeywords from './pages/ExcludeKeywords';
import Media from './pages/Media';
import Settings from './pages/Settings';
import ApiUsage from './pages/ApiUsage';
import Experiences from './pages/Experiences';
import ExperienceEnquiries from './pages/ExperienceEnquiries';
import ExperienceReviews from './pages/ExperienceReviews';
import AuditTrail from './pages/AuditTrail';
import Legal from './pages/Legal';
import Sessions from './pages/Sessions';
import OfficialStories from './pages/OfficialStories';
import {
  CompassIcon, UsersIcon, MapPinIcon, CreditCardIcon, MegaphoneIcon, ImageIcon, SettingsIcon,
  ClipboardCheckIcon, TrendingUpIcon, EyeOffIcon, TicketIcon, InboxIcon, ShieldIcon, MonitorIcon,
  StarIcon, BookOpenIcon,
} from './components/Icons';

/**
 * Every admin page, in sidebar order. The sidebar, the header title and the
 * routes are all built from this one list — adding a page is one entry here.
 * `badge` names a live count the sidebar shows next to the item.
 */
export const NAV_SECTIONS = [
  {
    label: 'Main Menu',
    items: [
      { path: '/dashboard', label: 'Dashboard', title: 'Dashboard Overview', icon: CompassIcon, page: Dashboard },
      { path: '/exclude-keywords', label: 'Exclude Keywords', title: 'Exclude Keywords (Around You)', icon: EyeOffIcon, page: ExcludeKeywords },
      { path: '/media', label: 'Media Library', title: 'Media Library', icon: ImageIcon, page: Media },
      { path: '/stories', label: 'nexARound Stories', title: 'nexARound Stories', icon: BookOpenIcon, page: OfficialStories },
    ],
  },
  {
    label: 'Map Database',
    items: [
      { path: '/places', label: 'All places', title: 'Map Database · All places', icon: MapPinIcon, page: Places },
      { path: '/places/review', label: 'Review queue', title: 'Map Database · Review queue', icon: ClipboardCheckIcon, page: ReviewQueue, badge: 'pending' },
    ],
  },
  {
    label: 'Business',
    items: [
      { path: '/experiences', label: 'Experiences', title: 'Experiences & Vendors', icon: TicketIcon, page: Experiences },
      { path: '/enquiries', label: 'Enquiries', title: 'Experience Enquiries', icon: InboxIcon, page: ExperienceEnquiries },
      { path: '/reviews', label: 'Reviews', title: 'Experience Reviews', icon: StarIcon, page: ExperienceReviews },
      { path: '/legal', label: 'Legal & Terms', title: 'Legal & Terms', icon: ClipboardCheckIcon, page: Legal },
      { path: '/payments', label: 'Payments & Plans', title: 'Payments & Plans', icon: CreditCardIcon, page: Payments },
    ],
  },
  {
    label: 'System',
    items: [
      { path: '/users', label: 'User Management', title: 'Explorer Management', icon: UsersIcon, page: Users },
      { path: '/engagement', label: 'Engagement', title: 'Engagement & Broadcasting', icon: MegaphoneIcon, page: Engagement },
      { path: '/api-usage', label: 'API Usage', title: 'API Usage & Cost', icon: TrendingUpIcon, page: ApiUsage },
      { path: '/audit', label: 'Audit Trail', title: 'Audit Trail', icon: ShieldIcon, page: AuditTrail },
      { path: '/sessions', label: 'Devices & Sessions', title: 'Devices & Sessions', icon: MonitorIcon, page: Sessions },
      { path: '/settings', label: 'Settings', title: 'General Settings', icon: SettingsIcon, page: Settings },
    ],
  },
];

export const NAV_ITEMS = NAV_SECTIONS.flatMap((section) => section.items);

// Old addresses that still arrive from bookmarks: [from, to].
export const NAV_REDIRECTS = [
  ['/attractions', '/places'],
  ['/approvals', '/places/review'],
];

export const HOME_PATH = '/dashboard';
export const LOGIN_PATH = '/login';
