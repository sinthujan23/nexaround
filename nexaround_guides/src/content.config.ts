import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';
import { PILLAR_KEYS } from './data/pillars';

const credit = z.object({
  author: z.string(),
  license: z.string(),
  licenseUrl: z.string().optional(),
  source: z.string(),
});

const guides = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/guides' }),
  schema: ({ image }) =>
    z.object({
      title: z.string(),
      // Meta description, and the line under the title.
      description: z.string().max(200),
      pillar: z.enum(PILLAR_KEYS as [string, ...string[]]),
      country: z.string(),
      region: z.string().optional(),
      cover: image(),
      coverAlt: z.string(),
      coverCredit: credit,
      // Opening paragraphs, shown before the route map. Blank line = new paragraph.
      intro: z.string().optional(),
      lastChecked: z.coerce.date(),
      published: z.coerce.date().optional(),
      // Up to four headline numbers under the title.
      facts: z.array(z.object({ value: z.string(), label: z.string() })).max(4).default([]),
      // Key of a file in src/data/routes/ holding the route lines to draw.
      route: z.string().optional(),
      routeLines: z
        .array(z.object({ key: z.string(), label: z.string(), dashed: z.boolean().default(false) }))
        .default([]),
      legs: z
        .array(z.object({ from: z.string(), to: z.string(), km: z.number(), min: z.number() }))
        .default([]),
      legsNote: z.string().optional(),
      stops: z
        .array(
          z.object({
            name: z.string(),
            lat: z.number(),
            lng: z.number(),
            kind: z.enum(['town', 'fuel', 'free', 'paid']).default('town'),
            note: z.string().optional(),
          }),
        )
        .default([]),
      photos: z
        .array(z.object({ src: image(), alt: z.string(), caption: z.string().optional(), credit }))
        .default([]),
      sources: z.array(z.object({ title: z.string(), url: z.string() })).default([]),
      affiliates: z
        .array(z.object({ program: z.enum(['airalo', 'gettransfer']), country: z.string().optional() }))
        .default([]),
      related: z.array(z.string()).default([]),
      // A guide stays a draft until the team has edited it and done every item in `todo`.
      draft: z.boolean().default(true),
      todo: z.array(z.string()).default([]),
    }),
});

export const collections = { guides };
