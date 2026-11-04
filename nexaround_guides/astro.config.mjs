import { readdirSync, readFileSync } from 'node:fs';
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

const SITE = 'https://guides.nexaround.com';

// Sitemap <lastmod>: each guide's lastChecked date; the home page and each
// section page take the newest date of the guides they list.
const lastmod = new Map();
const newer = (url, date) => { if (!lastmod.has(url) || lastmod.get(url) < date) lastmod.set(url, date); };
for (const file of readdirSync('src/content/guides').filter((f) => f.endsWith('.md'))) {
  const front = readFileSync(`src/content/guides/${file}`, 'utf8').split('\n---')[0];
  const field = (key) => front.match(new RegExp(`^${key}:\\s*(\\S+)`, 'm'))?.[1];
  if (field('draft') !== 'false' || !field('lastChecked')) continue;
  const date = field('lastChecked');
  newer(`${SITE}/${field('pillar')}/${file.slice(0, -3)}/`, date);
  newer(`${SITE}/${field('pillar')}/`, date);
  newer(`${SITE}/`, date);
}

// Preview builds (SITE_MODE=preview) include drafts and tell search engines
// to stay away; see src/lib/mode.ts.
export default defineConfig({
  site: SITE,
  trailingSlash: 'always',
  build: { format: 'directory' },
  integrations: [
    sitemap({
      // /app/ only redirects to the app stores: keep it out of the sitemap.
      filter: (page) => !page.endsWith('/app/'),
      serialize: (item) => (lastmod.has(item.url) ? { ...item, lastmod: lastmod.get(item.url) } : item),
    }),
  ],
});
