// Links that send readers to the nexARound app, tagged so we can see which
// guides and which spots on the page bring installs.
//
// Google Play passes `referrer` through to Play Console (Acquisition reports:
// utm_source = guides, utm_medium = where on the page, utm_campaign = guide).
// App Store campaign links need a provider token (`pt`) from App Store Connect;
// until we have it, Apple links are untagged.
import { STORES } from '../site';

export const PLAY_ID = 'com.nexaround.app';

export function playLink(medium: string, campaign = 'site') {
  const referrer = `utm_source=guides&utm_medium=${medium}&utm_campaign=${campaign}`;
  return `https://play.google.com/store/apps/details?id=${PLAY_ID}&referrer=${encodeURIComponent(referrer)}`;
}

export const appleLink = () => STORES.apple;

/** Our own /app/ page: sends phones to the right store, shows a QR code on computers. */
export const getAppLink = (medium: string, campaign = 'site') => `/app/?m=${encodeURIComponent(medium)}&c=${encodeURIComponent(campaign)}`;
