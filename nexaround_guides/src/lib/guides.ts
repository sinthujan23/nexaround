import { getCollection, type CollectionEntry } from 'astro:content';
import { isPreview, withTranslations } from './mode';

export type Guide = CollectionEntry<'guides'>;
export type Translation = CollectionEntry<'translations'>;

/** Translations of published guides, keyed `<lang>/<slug>`. */
export async function getTranslations(guides: Guide[]): Promise<Map<string, Translation>> {
  if (!withTranslations) return new Map();
  const ids = new Set(guides.map((g) => g.id));
  const all = await getCollection('translations', (t: Translation) => ids.has(t.data.guide));
  return new Map(all.map((t: Translation) => [`${t.data.lang}/${t.data.guide}`, t]));
}

/** Published guides, plus drafts in preview builds; newest first. */
export async function getGuides(): Promise<Guide[]> {
  const all = await getCollection('guides', (g: Guide) => isPreview || !g.data.draft);
  return all.sort((a: Guide, b: Guide) => dateOf(b) - dateOf(a));
}

const dateOf = (g: Guide) => (g.data.published ?? g.data.lastChecked).getTime();

export const guideUrl = (g: Guide) => `/${g.data.pillar}/${g.id}/`;

export function readMinutes(g: Guide | Translation): number {
  const words = (g.body ?? '').split(/\s+/).filter(Boolean).length;
  return Math.max(3, Math.round(words / 220));
}

export const formatDate = (d: Date) =>
  d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' });

export const formatKm = (km: number) => `${km.toLocaleString('en-US')} km`;

export function formatDuration(min: number): string {
  const h = Math.floor(min / 60);
  const m = min % 60;
  return h ? `${h} h ${String(m).padStart(2, '0')}` : `${m} min`;
}
