// /sitemap.xml: the same index as /sitemap-index.xml (made by @astrojs/sitemap),
// kept because this address may already be submitted to Search Console.
import type { APIContext } from 'astro';

export function GET({ site }: APIContext) {
  const body = `<?xml version="1.0" encoding="UTF-8"?><sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><sitemap><loc>${new URL('sitemap-0.xml', site).href}</loc></sitemap></sitemapindex>`;
  return new Response(body, { headers: { 'Content-Type': 'application/xml; charset=utf-8' } });
}
