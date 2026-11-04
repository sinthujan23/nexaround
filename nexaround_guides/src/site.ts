export const SITE = {
  name: 'nexARound Guides',
  tagline: 'Remote and unusual places',
  description:
    'Guides to remote and unusual places: road trips, extreme places and end-of-the-road villages, with checked distances, fuel gaps, permits and free stops.',
  publisher: 'NEXAROUND TECHNOLOGIES LLC',
  email: 'support@nexaround.com',
  appSite: 'https://app.nexaround.com',
};

// Same links as nexaround_landing/src/components/StoreButtons.jsx.
export const STORES = {
  play: 'https://play.google.com/store/apps/details?id=com.nexaround.app&pli=1',
  apple: 'https://apps.apple.com/app/nexaround/id6806252363',
};

// Travelpayouts. `trs` is the guides site's own project ID: leave it empty
// until that project exists, and affiliate boxes stay hidden. Never reuse the
// app's project (577812) here.
export const TRAVELPAYOUTS = {
  marker: '781739',
  trs: '',
};

// Cloudflare Web Analytics token (cookieless). Empty = no analytics script.
export const ANALYTICS = {
  cloudflareToken: '',
};
