# nexARound — Cinematic Ad Video: Prompt Pack

**Format:** 45-second hero spot (also cut-down to 15 s, see end) · 9:16 vertical master (Reels / TikTok / Shorts), 16:9 alt reframe
**Tagline (from the logo):** *Discover what's next around you.*
**Product truth:** AI travel companion. Point your phone → AR labels the real world. Ask Neva (AI guide) anything. Odyssey plans a whole trip (flights, stays, day-by-day, budget). Discover finds food / nature / medical / shopping nearby. Museum Mode, local Experiences, walking challenges.

---

## 1. How to use this pack

1. Upload the images in `assets/` as **reference / first-frame images** (the table in §3 says which image goes with which shot).
2. Generate each shot separately (5–8 s each) with its **Shot prompt** (§5), pasted after the **Master style block** (§4).
3. **Do NOT let the video model render the app UI.** AI video models garble on-screen text. Generate the phone as a *blank/dark glowing screen* and composite the real screenshots (`12_`–`14_`) in post (CapCut / Premiere / After Effects screen-replace). Shots 3, 5, 6 are written this way.
4. Add logo end card, captions and music in the editor, not in the generator.

> Heads-up on the supplied assets: `05_ar_mode_hero.png` and `06_odyssey_globe.png` are AI-generated mock-ups, and the label text inside them is gibberish ("Rasothurol Co…", "Hotel Rasa Male", garbled "NE" chips). Use them as **mood/composition references only**, not as footage of the real UI. The logo files are small (≈300 px tall); for a crisp end card, re-export the logo from the original vector/Figma source if you have one.

---

## 2. Brand look

| | |
|---|---|
| Palette | Deep navy `#0B2A5B` (logo pin) · brand teal `#007A7C` (app accent) · leaf green `#43A047`/`#00E676` neon (route ribbon, AR highlights) · compass orange-red `#D9542B` · warm gold `#FFB800` (ratings) · near-black `#121212` |
| Feel | Premium, optimistic, "magic made real". Warm golden-hour travel footage + clean teal/green holographic AR overlays. Not techy-cold, not stock-corporate. |
| App UI | White cards, black pill buttons, rounded 16–24 px corners, Outfit-style geometric sans. |
| Motion language | The logo's **curving road/ribbon** is the signature: a glowing teal-to-green path that threads through every scene and ends by forming the logo's road. |

---

## 3. Asset → shot map

| Asset (`assets/`) | Use it for |
|---|---|
| `01_logo_transparent.png` | End card, corner watermark |
| `02_logo_lockup_tagline.png` | End card with tagline (reference for logo colours/shape) |
| `03_neva_character_ref.png` | **Character reference for Neva** — shots 4 & 7. Pixar-style 3D woman, shoulder-length brown bob with bangs, olive-green eyes, silver stud earrings, navy knit sweater. Keep her identical across shots. |
| `04_neva_walking.webp` | Neva walking cycle (256 px, motion reference only) |
| `05_ar_mode_hero.png` | Composition reference, shot 3 (hand holding phone, golden-hour city, floating label cards) |
| `06_odyssey_globe.png` | First frame / reference, shot 5 (glowing globe, brass compass base, vintage camera, neon route ring) |
| `07_destination_tropical.png` | Shot 6 destination (overwater bungalows, turquoise lagoon, sunset) |
| `08_destination_lotus_temple.png` | Shot 2 or 6 destination variety |
| `09_museum_mode.png` | Optional shot (Museum Mode), neon-green night architecture |
| `10_experiences.png`, `11_walking_challenge.jpg` | B-roll references for 15 s variants |
| `12_screen_discover_food.png`, `13_…nature`, `14_…medical` | **Real UI screenshots to composite onto the phone** (shots 5/6/8) |
| `15_screen_journal.png` | Not recommended (plain form, weak visually) |
| `16_feature_graphic_style_ref.png` | Existing brand graphic, colour/style check |
| `17_`, `18_` mp4 | Existing in-app motion banners, reusable as transition plates |

---

## 4. Master style block (paste before every shot prompt)

```
Cinematic travel commercial, shot on ARRI Alexa 35 with anamorphic lenses, 2.0x squeeze flares subtle, shallow depth of field, natural film grain, soft halation on highlights. Warm golden-hour palette (amber, peach) contrasted with clean teal (#007A7C) and leaf-green holographic AR overlays. Premium, optimistic, aspirational mood. Smooth gimbal and slow dolly movement, no shaky cam. Photorealistic people with natural skin texture and diverse ethnicities; hands and fingers anatomically correct. Recurring motif: a thin glowing teal-to-green ribbon of light that curves like a winding road. 9:16 vertical, 24 fps, 4K look.
```

## 4b. Negative prompt

```
no readable text, no captions, no watermarks, no logos other than provided, no garbled lettering on screens, no extra fingers, no distorted hands, no phone brand logos, no cartoonish look on real-world scenes, no heavy orange-teal oversaturation, no jitter, no flicker, no morphing buildings, no stock-photo smiles
```

---

## 5. Shot list (45 s)

> Voice-over (calm, warm, female; Neva's voice or neutral narrator) is in *italics*. Total ≈ 80 words.

### Shot 1 — The itch (0:00–0:05)
*"Every trip starts with a question…"*
**Refs:** none (text-to-video).
```
Dawn, a young traveller (late 20s, South-Asian woman, linen shirt, small backpack) stands at a rooftop edge overlooking an unfamiliar ancient city waking up, terracotta roofs, minarets, mist in the valleys. Slow push-in from behind her shoulder, then she glances down at her phone and lifts it. Soft golden rim light, birds crossing frame, lens flare. Quiet, curious, anticipatory mood. 5 seconds.
```

### Shot 2 — The world is unlabeled (0:05–0:11)
*"…What is that? Where do I eat? Is it worth the walk?"*
**Ref (optional):** `08_destination_lotus_temple.png`.
```
Street-level tracking shot through a lively old-town market at golden hour: spice stalls, lanterns, scooters, a landmark building glowing in the background. A tourist looks around, slightly lost, turning on the spot as the camera orbits her 180 degrees; the crowd moves in gentle slow motion around her. Shallow depth of field, warm haze, anamorphic bokeh. 6 seconds.
```

### Shot 3 — AR magic (0:11–0:18)
*"nexARound turns your camera into a guide."*
**Ref:** `05_ar_mode_hero.png` (composition only). **Composite real UI in post.**
```
Over-the-shoulder shot of the traveller raising her smartphone toward the market street; the phone screen is a dark glass surface with a soft teal glow (blank, no UI). As she raises it, thin glowing teal and green holographic label cards and dotted anchor lines bloom in 3D space in the REAL street itself, floating above the landmark, a café and a pharmacy, each card a small rounded black pill with a star glyph and a tiny distance marker, no legible text. The labels settle with a gentle spring ease. Camera slow dolly-in and rack focus from phone to the glowing street. Wonder, delight. 7 seconds.
```

### Shot 4 — Meet Neva (0:18–0:24)
*"Ask Neva anything — history, food, budgets, hidden gems."*
**Ref:** `03_neva_character_ref.png` (keep face, hair, sweater identical).
```
The 3D animated Pixar-style character from the reference image (shoulder-length brown bob with bangs, olive-green eyes, silver stud earrings, navy knit sweater) appears as a friendly holographic presence beside the traveller, at chest height, as a softly glowing translucent figure that materialises out of teal light particles. She smiles warmly, tilts her head and gestures toward the building; a thin green ribbon of light trails from her gesture across the frame. Character consistent with the reference, expressive eyes, subtle lip-sync-ready mouth closed in a smile. Soft rim light, background market blurred. 6 seconds.
```

### Shot 5 — Plan a whole trip (0:24–0:31)
*"Plan the whole journey in seconds — flights, stays, every day, every dollar."*
**Ref / first frame:** `06_odyssey_globe.png`.
```
Start from the reference image: a luminous holographic globe on a brass compass-rose base on a dark wooden table, a vintage rangefinder camera and a pocket compass beside it. Slow orbit of the camera as glowing teal-gold route lines draw themselves across continents, small teardrop pins pop up one by one, and a neon ring of light traces around the table. Then a smooth match-cut pull-back: the globe shrinks into a smartphone screen held in a hand (screen blank, soft glow) for UI composite. Dark, moody, premium; deep bokeh dust particles. 7 seconds.
```

### Shot 6 — Go (0:31–0:38)
*"Then just… go."*
**Ref:** `07_destination_tropical.png`.
```
Cinematic drone shot flying low over a turquoise lagoon toward thatched overwater bungalows at sunset, mountains wrapped in cloud behind. The glowing teal-green ribbon of light unspools along the water from the foreground and curves toward the bungalows like a road, then lifts into the sky. Cut to a close-up of the traveller on the pier, barefoot, laughing, phone lowered in her hand, wind in hair, golden sun flare. Slow motion 60 fps conformed to 24. Freedom, joy. 7 seconds.
```

### Shot 7 — Everywhere you land (0:38–0:42)
*"Food. Nature. Museums. Help when you need it."*
**Refs:** `12_`, `13_`, `14_` screenshots (composite), `09_museum_mode.png` (mood).
```
Fast, rhythmic montage of four 1-second shots, no text: (a) hands tearing flatbread over steaming street food; (b) a hiker on a ridge at sunrise looking across a misty valley; (c) a visitor gazing up at a glowing neon-green night museum façade; (d) a calm pharmacy interior with a soft green cross light. Each shot ends on a hard cut synchronised to a musical beat, with a thin teal ribbon of light wiping across the frame as a transition. Warm, human, trustworthy. 4 seconds.
```

### Shot 8 — End card (0:42–0:45)
*"nexARound. Discover what's next around you."*
**Ref:** `02_logo_lockup_tagline.png`, `01_logo_transparent.png`.
```
The glowing teal-to-green ribbon of light sweeps across a deep navy background and settles into the shape of the nexARound logo: a navy location pin with an orange-red compass needle above a winding blue-and-green road. Soft light bloom, floating particles, then clean hold. Minimal, elegant, centred, lots of negative space. 3 seconds.
```
**In post:** replace the generated logo with the real `01_logo_transparent.png` (generators mangle logos), add tagline in the app's sans font, Google Play / App Store badges, and `nexaround.com`.

---

## 6. Audio

- **Music:** cinematic-uplifting build — sparse piano and a soft pulse for 0:00–0:11, strings and percussion swell into the AR reveal (0:11), full arrangement at "Then just… go" (0:31), clean resolve into a single chime on the logo. 100–110 BPM, hits on cuts.
  Music-generator prompt: *"Uplifting cinematic travel-ad score, warm piano intro, building strings and soft electronic pulse, hopeful and adventurous, resolves with a bright single chime, 45 seconds, instrumental."*
- **SFX:** market ambience (0:05), soft "shimmer" as AR labels bloom (0:11), gentle UI pop on each pin (0:24–0:31), waves + wind (0:31), whoosh on each montage cut (0:38).
- **Voice-over (≈ 80 words):**
  > Every trip starts with a question. What is that? Where do I eat? Is it worth the walk? nexARound turns your camera into a guide. Ask Neva anything — history, food, budgets, hidden gems. Plan the whole journey in seconds: flights, stays, every day, every dollar. Then just… go. Food. Nature. Museums. Help when you need it. nexARound. Discover what's next around you.

---

## 7. On-screen captions (post)

| Time | Caption |
|---|---|
| 0:11 | Point. See. Know. |
| 0:18 | Meet Neva, your AI guide |
| 0:24 | Plan the whole trip in seconds |
| 0:38 | Food · Nature · Museums · Help |
| 0:42 | **nexARound** — Discover what's next around you |

---

## 8. 15-second cut-down (for ads)

| Time | Shot |
|---|---|
| 0:00–0:03 | Shot 2 (lost in the market) |
| 0:03–0:08 | Shot 3 (AR labels bloom) + real UI composite |
| 0:08–0:11 | Shot 4 (Neva) |
| 0:11–0:13 | Shot 6 (tropical lagoon) |
| 0:13–0:15 | Shot 8 (end card) |

---

## 9. Generation tips

- Use **image-to-video** wherever a ref is listed; text-to-video for shots 1, 2, 7.
- Generate 3–4 takes per shot and pick the best. Keep Neva's reference attached on every shot she appears in.
- If the model garbles label cards in shot 3, regenerate with "blank empty rounded dark rectangles" and add real labels as animated motion-graphics layers.
- Keep clips ≤ 8 s; longer clips drift.
- Colour-grade all shots together at the end (same teal/amber LUT) so the scenes feel like one film.
