export const PILLARS = {
  'road-trips': {
    name: 'Road trips',
    short: 'Long roads, leg by leg',
    intro: 'The long roads: every leg measured, every fuel gap marked, and where to stop for free.',
  },
  'extreme-places': {
    name: 'Extreme places',
    short: 'Coldest, wettest, highest',
    intro: 'The coldest, wettest, highest and most remote places people live, and how to actually get there.',
  },
  'remote-villages': {
    name: 'Remote villages',
    short: 'At the end of the road',
    intro: 'Villages at the end of the road, or past it: how to reach them and how to visit with respect.',
  },
  'free-stops': {
    name: 'Free stops',
    short: 'Lookouts, rest areas, springs',
    intro: 'Lookouts, rest areas, ruins and springs that cost nothing, along the routes we cover.',
  },
  'know-how': {
    name: 'Know-how',
    short: 'Permits, fuel, no signal',
    intro: 'The practical side of remote travel: permits, fuel range, water, and planning without phone signal.',
  },
} as const;

export type PillarKey = keyof typeof PILLARS;
export const PILLAR_KEYS = Object.keys(PILLARS) as PillarKey[];
