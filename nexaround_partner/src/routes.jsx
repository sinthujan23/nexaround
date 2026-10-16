import { matchPath } from 'react-router-dom';
import {
  ClipboardCheckIcon, CompassIcon, TicketIcon, InboxIcon, MapPinIcon, ShieldIcon, StarIcon,
} from './components/Icons';

/**
 * The sidebar, in order. The route tree in App.jsx holds the pages; this list
 * holds what the shell needs to draw around them. Adding a section is one
 * entry here plus its routes there.
 */
export const NAV_ITEMS = [
  { to: '/dashboard', label: 'Dashboard', Icon: CompassIcon },
  { to: '/packages', label: 'My Packages', Icon: TicketIcon },
  { to: '/enquiries', label: 'Enquiries', Icon: InboxIcon, badge: 'enquiries' },
  { to: '/reviews', label: 'Reviews', Icon: StarIcon },
  { to: '/profile', label: 'Business Profile', Icon: MapPinIcon },
  { to: '/security', label: 'Security', Icon: ShieldIcon },
  { to: '/agreement', label: 'Provider Agreement', Icon: ClipboardCheckIcon },
];

/**
 * What the shell prints above each page, matched top to bottom. `back` makes
 * a detail page show a link to its list. An entry with no `title` prints no
 * header (the dashboard's greeting is its own title).
 */
const HEADERS = [
  { path: '/dashboard', title: null },
  { path: '/packages/new', title: 'New package', back: { to: '/packages', label: 'My Packages' } },
  { path: '/packages/:packageId', title: 'Edit package', back: { to: '/packages', label: 'My Packages' } },
  { path: '/packages', title: 'My Packages' },
  { path: '/enquiries/:enquiryId', title: 'Enquiries' },
  { path: '/enquiries', title: 'Enquiries' },
  { path: '/reviews', title: 'Reviews' },
  { path: '/profile/*', title: 'Business Profile' },
  { path: '/security/*', title: 'Security & Devices' },
  { path: '/agreement', title: 'Provider Agreement' },
];

export function headerFor(pathname) {
  for (const entry of HEADERS) {
    if (matchPath({ path: entry.path, end: !entry.path.endsWith('/*') }, pathname)) return entry;
  }
  return null;
}
