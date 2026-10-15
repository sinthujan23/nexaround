import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// Preview builds (SITE_MODE=preview) include drafts and tell search engines
// to stay away; see src/lib/mode.ts.
export default defineConfig({
  site: 'https://guides.nexaround.com',
  trailingSlash: 'always',
  build: { format: 'directory' },
  // /app/ only redirects to the app stores: keep it out of the sitemap.
  integrations: [sitemap({ filter: (page) => !page.endsWith('/app/') })],
});
