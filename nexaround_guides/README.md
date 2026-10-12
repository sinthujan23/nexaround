# nexARound Guides

The travel-guides site at **https://guides.nexaround.com**: remote and unusual places.
It's a static site built with [Astro](https://astro.build), styled to match app.nexaround.com.
Every guide is one Markdown file.

The topic list, templates and publishing checklist are in [EDITORIAL_PLAN.md](EDITORIAL_PLAN.md).

## Edit a guide

Guides live in `src/content/guides/<slug>.md`. The file name becomes the address:
`adelaide-to-perth-nullarbor.md` → `/road-trips/adelaide-to-perth-nullarbor/`.

The top of the file, between the `---` lines, holds the guide's data. Below it is the article text.

| Field | What it is |
| --- | --- |
| `title`, `description` | Title, and the line under it (also what Google shows; 200 characters max) |
| `pillar` | `road-trips`, `extreme-places`, `remote-villages`, `free-stops` or `know-how` |
| `country`, `region` | Shown on the card and in the header |
| `cover`, `coverAlt`, `coverCredit` | Header photo, its description, and who took it plus the licence |
| `intro` | Opening paragraphs, shown before the map |
| `lastChecked` | The date someone last checked the facts. Update it whenever you re-check. |
| `facts` | Up to four headline numbers under the title |
| `route`, `routeLines`, `legs`, `stops` | Map and leg table (see "Measure a route" below) |
| `photos` | Extra photos, each with a caption and credit |
| `sources` | Links to where each fact came from |
| `affiliates` | Partner boxes (`airalo`, `gettransfer`); hidden until the Travelpayouts project exists |
| `draft` | `true` until the guide is edited and ready |
| `todo` | What the team must do before publishing. It shows as a yellow box on drafts. |

Article text is plain Markdown: `## Heading`, `**bold**`, lists, `| tables |`. Each `##` heading
appears in the "On this page" menu.

### Photos

Put images in `src/assets/guides/<slug>/`, at most about 2000 px wide. The build makes WebP
versions in several sizes. Only use photos that are:
- our own, or sent by the photographer with permission (credit them by name), or
- under a free licence (Wikimedia Commons CC BY / CC BY-SA). Give the author, the licence
  and a link to the source file in the credit.

Never use AI-generated pictures of real places.

### Publish a guide

1. Work through every item in its `todo` list, then delete the list.
2. Set `draft: false` and update `lastChecked`.
3. Remove the guide from `src/data/upcoming.ts` if it's listed there.
4. Build (below).

## Preview while editing

```sh
npm install        # first time only
npm run dev        # http://localhost:4321 (shows drafts)
```

## Build and deploy (on the server)

nginx serves `dist/` directly, so a new build is live as soon as it finishes. No restart is needed.

```sh
cd /var/www/nexaround/nexaround_guides
git pull
npm ci
npm run build           # the public site: published guides only, indexable (LIVE since 12 Oct 2026)
npm run build:preview   # review drafts privately: drafts shown, every page noindex, robots.txt blocks crawlers
```

The site went **public on 12 October 2026** with all 20 guides published. Always deploy with
`npm run build`; a `build:preview` deploy would hide the site from Google. To review a new draft
without publishing it, use `npm run dev` instead.

**Follow-up checks:** the guides were published before the team's checks were done. The open
items are listed at the end of `EDITORIAL_PLAN.md`.

## Launch checklist

- [x] Guides published (12 Oct 2026); follow-up checks listed in EDITORIAL_PLAN.md.
- [ ] Cloudflare Web Analytics token in `src/site.ts` (`ANALYTICS.cloudflareToken`).
- [ ] Google Search Console: verify the domain (DNS TXT record at Hostinger), submit `/sitemap-index.xml`.
- [x] Built with `npm run build` (public mode).
- [ ] Create a **new** Travelpayouts project (type: website) for https://guides.nexaround.com,
      and put its project ID in `src/site.ts` (`TRAVELPAYOUTS.trs`). Never reuse the app's project (577812).

## Measure a route

Road-trip guides get their leg table and map line from Google Directions:

```sh
GOOGLE_MAPS_API_KEY=... python3 scripts/measure_route.py my-route.json adelaide-perth
```

See the top of `scripts/measure_route.py` for the input format. Use each stop's exact
coordinates, not its name: Google turns some names into a point off the highway, and
the distances come out wrong.

## Where things are

- `src/pages/`: home, section pages (`[pillar]/`), the guide page (`[pillar]/[slug].astro`), About and other text pages
- `src/components/`: nav, footer, cards, route map (Leaflet + OpenStreetMap), leg table, partner box
- `src/styles/global.css`: all styling. Tokens and components follow `nexaround_landing/src/index.css`.
- `src/site.ts`: store links, contact email, Travelpayouts and analytics settings
- `src/data/`: section names, "in the works" list, route lines
- nginx: the `guides.nexaround.com` block in `/etc/nginx/sites-available/nexaround` (outside git)
