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
import VendorChanges from './pages/VendorChanges';
import ProviderApplications from './pages/ProviderApplications';
import AuditTrail from './pages/AuditTrail';
import Legal from './pages/Legal';
import Sessions from './pages/Sessions';
import OfficialStories from './pages/OfficialStories';
import CityTours, { CityTourQueue } from './pages/CityTours';
import CityTourEditor from './pages/CityTourEditorLazy';
import CityTourTaps from './pages/CityTourTaps';
import CityTourCreators from './pages/CityTourCreators';
import { ADMIN, CREATOR } from './session';
import {
  CompassIcon, UsersIcon, MapPinIcon, CreditCardIcon, MegaphoneIcon, ImageIcon, SettingsIcon,
  ClipboardCheckIcon, TrendingUpIcon, EyeOffIcon, TicketIcon, InboxIcon, ShieldIcon, MonitorIcon,
  StarIcon, BookOpenIcon, RouteIcon,
} from './components/Icons';

// Pages a content creator may open too. Every other page is admin-only.
const BOTH = [ADMIN, CREATOR];

/**
 * Every admin page, in sidebar order. The sidebar, the header title and the
 * routes are all built from this one list — adding a page is one entry here.
 * `badge` names a live count the sidebar shows next to the item. `roles`
 * says who may open it (admins only when absent); `hidden` pages have a route
 * but no sidebar entry; `creatorLabel` is the sidebar name creators see.
 */
export const NAV_SECTIONS = [
  {
    label: 'Main Menu',
    items: [
      { path: '/dashboard', label: 'Dashboard', title: 'Dashboard Overview', icon: CompassIcon, page: Dashboard },
      { path: '/exclude-keywords', label: 'Exclude Keywords', title: 'Exclude Keywords (Around You)', icon: EyeOffIcon, page: ExcludeKeywords },
      { path: '/media', label: 'Media Library', title: 'Media Library', icon: ImageIcon, page: Media },
      { path: '/stories', label: 'TravelByte Stories', title: 'TravelByte Stories', icon: BookOpenIcon, page: OfficialStories },
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
      { path: '/experiences/changes', label: 'Vendor changes', title: 'Experiences · Vendor changes', icon: ClipboardCheckIcon, page: VendorChanges, badge: 'vendor_changes' },
      { path: '/enquiries', label: 'Enquiries', title: 'Experience Enquiries', icon: InboxIcon, page: ExperienceEnquiries, badge: 'enquiries' },
      { path: '/experiences/applications', label: 'Provider applications', title: 'Experiences · Provider applications', icon: UsersIcon, page: ProviderApplications, badge: 'provider_applications' },
      { path: '/reviews', label: 'Reviews', title: 'Experience Reviews', icon: StarIcon, page: ExperienceReviews },
      { path: '/legal', label: 'Legal & Terms', title: 'Legal & Terms', icon: ClipboardCheckIcon, page: Legal },
      { path: '/payments', label: 'Payments & Plans', title: 'Payments & Plans', icon: CreditCardIcon, page: Payments },
    ],
  },
  {
    label: 'City Tours',
    items: [
      { path: '/city-tours', label: 'Guides', creatorLabel: 'My guides', title: 'City Tours · Guides', icon: RouteIcon, page: CityTours, roles: BOTH },
      { path: '/city-tours/review', label: 'Review queue', title: 'City Tours · Review queue', icon: ClipboardCheckIcon, page: CityTourQueue, badge: 'city_tours' },
      { path: '/city-tours/taps', label: 'Partner taps', title: 'City Tours · Partner taps', icon: TrendingUpIcon, page: CityTourTaps },
      { path: '/city-tours/creators', label: 'Creators', title: 'City Tours · Content creators', icon: UsersIcon, page: CityTourCreators },
      { path: '/city-tours/edit', label: 'Guide', title: 'City Tours · Guide', icon: RouteIcon, page: CityTourEditor, roles: BOTH, hidden: true },
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

export const canSee = (item, role) => (item.roles || [ADMIN]).includes(role);

/** The sidebar for this role: pages it may open, hidden ones left out. */
export const navSectionsFor = (role) => NAV_SECTIONS
  .map((section) => ({ ...section, items: section.items.filter((item) => !item.hidden && canSee(item, role)) }))
  .filter((section) => section.items.length > 0);

export const homePathFor = (role) => (role === CREATOR ? '/city-tours' : HOME_PATH);
