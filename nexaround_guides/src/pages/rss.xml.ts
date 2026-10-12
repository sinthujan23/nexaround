import rss from '@astrojs/rss';
import type { APIContext } from 'astro';
import { getGuides, guideUrl } from '../lib/guides';
import { SITE } from '../site';

export async function GET(context: APIContext) {
  const guides = await getGuides();
  return rss({
    title: SITE.name,
    description: SITE.description,
    site: context.site!,
    items: guides.map((g) => ({
      title: g.data.title,
      description: g.data.description,
      pubDate: g.data.published ?? g.data.lastChecked,
      link: guideUrl(g),
    })),
  });
}
