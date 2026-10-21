// Data for the interactive parts of the home page. Every figure here comes
// from a published guide's facts or body; update it when a guide changes.

// Hero slideshow: each slide shows a guide's cover photo (and its credit).
export const HERO_SLIDES = [
  { guide: 'adelaide-to-perth-nullarbor', place: 'Bunda Cliffs, South Australia' },
  { guide: 'karakoram-highway', place: 'Attabad Lake, Karakoram Highway' },
  { guide: 'westfjords-iceland', place: 'Dynjandi, the Westfjords of Iceland' },
  { guide: 'pamir-highway', place: 'Karakul Lake, Pamir Highway' },
];

// World map pins. Guides that sit close together share a pin. Coordinates
// are where the pin goes, not exact places: Coober Pedy is nudged 1° north
// so its pin does not cover the Nullarbor one, and the Pamir/Karakoram pin
// sits north-west of both roads to leave room for Turtuk. A guide with no
// entry here gets no pin; drafts stay off the map until they are published.
export const MAP_PLACES = [
  { label: 'The Nullarbor, Australia', lat: -31.9, lng: 128.6, continent: 'Oceania', guides: ['adelaide-to-perth-nullarbor', 'free-stops-nullarbor'] },
  { label: 'Coober Pedy, Australia', lat: -28.0, lng: 134.75, continent: 'Oceania', guides: ['coober-pedy'] },
  { label: 'Gibb River Road, Australia', lat: -16.5, lng: 126.0, continent: 'Oceania', guides: ['gibb-river-road', 'free-stops-gibb-river-road'] },
  { label: 'Meemure, Sri Lanka', lat: 7.43, lng: 80.92, continent: 'Asia', guides: ['meemure-sri-lanka'] },
  { label: 'Mawsynram and Cherrapunji, India', lat: 25.3, lng: 91.58, continent: 'Asia', guides: ['mawsynram-cherrapunji-monsoon'] },
  { label: 'Pamir and Karakoram highways', lat: 39.5, lng: 71.5, continent: 'Asia', guides: ['pamir-highway', 'karakoram-highway', 'free-stops-karakoram-highway'] },
  { label: 'Turtuk, Ladakh', lat: 34.85, lng: 76.83, continent: 'Asia', guides: ['turtuk-ladakh'] },
  { label: 'Yakutia and Kolyma, Russia', lat: 63.2, lng: 143.5, continent: 'Asia', guides: ['oymyakon-coldest-village', 'road-of-bones-yakutsk-magadan'] },
  { label: 'The Caucasus, Georgia', lat: 42.6, lng: 44.3, continent: 'Asia', guides: ['ushguli-georgia', 'tusheti-georgia'] },
  { label: 'Longyearbyen, Svalbard', lat: 78.22, lng: 15.63, continent: 'Europe', guides: ['longyearbyen-svalbard'] },
  { label: 'The Westfjords, Iceland', lat: 65.7, lng: -23.0, continent: 'Europe', guides: ['westfjords-iceland', 'free-stops-westfjords'] },
  { label: 'Gásadalur, Faroe Islands', lat: 62.11, lng: -7.44, continent: 'Europe', guides: ['gasadalur-faroe-islands'] },
  { label: 'Trans-Labrador Highway, Canada', lat: 52.9, lng: -66.9, continent: 'North America', guides: ['trans-labrador-highway'] },
  { label: 'Dalton Highway, Alaska', lat: 67.25, lng: -150.18, continent: 'North America', guides: ['dalton-highway', 'free-stops-dalton-highway'] },
  { label: 'Supai, Grand Canyon', lat: 36.24, lng: -112.69, continent: 'North America', guides: ['supai-havasupai'] },
  { label: 'Puno and La Rinconada, Peru', lat: -14.63, lng: -69.45, continent: 'South America', guides: ['la-rinconada', 'candelaria-puno'] },
  { label: 'Carretera Austral, Chile', lat: -45.57, lng: -72.07, continent: 'South America', guides: ['carretera-austral', 'free-stops-carretera-austral'] },
  { label: 'Puerto Williams, Chile', lat: -54.94, lng: -67.61, continent: 'South America', guides: ['puerto-williams'] },
  { label: 'Skeleton Coast, Namibia', lat: -19.0, lng: 13.0, continent: 'Africa', guides: ['skeleton-coast-kaokoland'] },
  { label: 'Tristan da Cunha', lat: -37.11, lng: -12.28, continent: 'Africa', guides: ['tristan-da-cunha'] },
  { label: 'Sani Pass, Lesotho', lat: -29.58, lng: 29.29, continent: 'Africa', guides: ['sani-pass-lesotho'] },
  { label: 'Lake Natron, Tanzania', lat: -2.6, lng: 35.9, continent: 'Africa', guides: ['lake-natron-tanzania'] },
  { label: 'Tsingy de Bemaraha, Madagascar', lat: -19.0, lng: 44.8, continent: 'Africa', guides: ['tsingy-de-bemaraha'] },
  { label: 'Aït Bouguemez, Morocco', lat: 31.66, lng: -6.43, continent: 'Africa', guides: ['ait-bouguemez-morocco'] },
  { label: 'Ganvié and Ouidah, Benin', lat: 6.47, lng: 2.41, continent: 'Africa', guides: ['ganvie-benin', 'vodun-days-ouidah'] },
  // Festivals: pins drawn in their own colour (WorldMap's .pin-fest).
  { label: 'Timkat, Addis Ababa', lat: 9.04, lng: 38.76, continent: 'Africa', kind: 'festival', guides: ['timkat-addis-ababa'] },
  { label: 'Up Helly Aa, Shetland', lat: 60.15, lng: -1.15, continent: 'Europe', kind: 'festival', guides: ['up-helly-aa-shetland'] },
  { label: 'Carnaval de Québec, Canada', lat: 46.81, lng: -71.21, continent: 'North America', kind: 'festival', guides: ['carnaval-de-quebec'] },
  { label: 'Waitangi Day, New Zealand', lat: -35.27, lng: 174.08, continent: 'Oceania', kind: 'festival', guides: ['waitangi-day'] },
  { label: 'Chinese New Year, Hong Kong', lat: 22.29, lng: 114.17, continent: 'Asia', kind: 'festival', guides: ['chinese-new-year'] },
  { label: 'Holi, Mathura and Vrindavan', lat: 27.5, lng: 77.68, continent: 'Asia', kind: 'festival', guides: ['holi-mathura-vrindavan'] },
  { label: 'Cherry blossom, Japan', lat: 35.69, lng: 139.75, continent: 'Asia', kind: 'festival', guides: ['hanami-japan'] },
  { label: 'Songkran, Thailand', lat: 18.79, lng: 98.99, continent: 'Asia', kind: 'festival', guides: ['songkran-thailand'] },
];

// The continent a guide's pin sits on, so search can match "Africa" and the like.
export const continentOf = (guideId: string) => MAP_PLACES.find((p) => p.guides.includes(guideId))?.continent ?? '';

// The dotted world map (public/world-dots.svg) is equirectangular, cropped
// to latitudes 82° N to 56° S.
export const mapPosition = (lat: number, lng: number) => ({
  x: ((lng + 180) / 360) * 100,
  y: ((82 - lat) / 138) * 100,
});

// "The extremes, measured" chart on the home page.
export const EXTREMES = [
  {
    key: 'fuel',
    name: 'No fuel for',
    hint: 'The longest gaps between pumps',
    title: 'Longest stretch with no fuel',
    sub: 'One gap per route, as measured in each guide.',
    note: 'Fill up at every pump on these roads, and carry enough to cover the next two gaps in case one is shut.',
    rows: [
      { label: 'Coldfoot to Deadhorse', sub: 'Dalton Highway, Alaska', value: 386, text: '386 km (240 mi)', guide: 'dalton-highway' },
      { label: 'Longest gap on the Gibb', sub: 'Gibb River Road, Australia', value: 330, text: 'About 330 km', guide: 'gibb-river-road' },
      { label: 'Glendambo to Coober Pedy', sub: 'Stuart Highway, Australia', value: 254, text: '254 km', guide: 'coober-pedy' },
      { label: 'Balladonia to Norseman', sub: 'Eyre Highway, the Nullarbor', value: 191, text: '191 km', guide: 'adelaide-to-perth-nullarbor' },
    ],
  },
  {
    key: 'high',
    name: 'Highest point',
    hint: 'Towns, villages and passes',
    title: 'Highest point you reach',
    sub: 'The town itself, or the top of the road, in metres.',
    note: 'Above about 2,500 m, altitude sickness is a real risk. Each guide covers how to acclimatise.',
    rows: [
      { label: 'La Rinconada', sub: 'Town, Peru', value: 5000, text: 'About 5,000 m', guide: 'la-rinconada' },
      { label: 'Near the Khunjerab Pass', sub: 'Karakoram Highway', value: 4714, text: '4,714 m', guide: 'karakoram-highway' },
      { label: 'Ak-Baital Pass', sub: 'Pamir Highway', value: 4655, text: '4,655 m', guide: 'pamir-highway' },
      { label: 'Ushguli', sub: 'Villages, Georgia', value: 2100, text: '2,100 m', guide: 'ushguli-georgia' },
      { label: 'Atigun Pass', sub: 'Dalton Highway, Alaska', value: 1444, text: '1,444 m (4,739 ft)', guide: 'dalton-highway' },
    ],
  },
  {
    key: 'far',
    name: 'How far out',
    hint: 'From the nearest gateway city',
    title: 'Distance from the gateway city',
    sub: 'By road, except Tristan da Cunha, which is by sea.',
    note: 'Distances are from the city each guide starts from, measured on the day we checked it.',
    rows: [
      { label: 'Tristan da Cunha', sub: 'From Cape Town, by sea', value: 2810, text: '2,810 km', guide: 'tristan-da-cunha' },
      { label: 'Oymyakon', sub: 'From Yakutsk', value: 922, text: '922 km', guide: 'oymyakon-coldest-village' },
      { label: 'Coober Pedy', sub: 'From Adelaide', value: 846, text: '846 km', guide: 'coober-pedy' },
      { label: 'La Rinconada', sub: 'From Juliaca', value: 164, text: '164 km', guide: 'la-rinconada' },
      { label: 'Meemure', sub: 'From Kandy', value: 78, text: '78 km', guide: 'meemure-sri-lanka' },
      { label: 'Ushguli', sub: 'From Mestia', value: 43, text: '43 km', guide: 'ushguli-georgia' },
    ],
  },
];

// Hero search shortcuts.
export const QUICK_SEARCHES = ['Nullarbor', 'Iceland', 'coldest', 'gravel'];
