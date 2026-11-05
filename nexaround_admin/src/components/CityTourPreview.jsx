import { Fragment, useEffect, useRef, useState } from 'react';
import { apiGet, mediaUrl } from '../api';
import { inlineRuns, parseBlocks } from '../descriptionFormat';
import { escapeHtml } from '../places';
import { allSteps, dayPlan, formatClock, modeOf, partnerLogo, stopNumbers } from '../cityTours';

// The guide as the app draws it, at the app's own sizes: a copy of
// nexaround_app/lib/features/city_tours/ (city_tour_page.dart and
// city_tour_widgets.dart). Change one, change the other.

// iPhone 17 Pro, in points: screen, top safe area (Dynamic Island) and the
// .ctp-phone frame around the screen.
const PHONE_W = 402;
const PHONE_H = 874;
const STATUS_BAR = 62;
const FRAME = 10;
const OUTER_W = PHONE_W + FRAME * 2;
const OUTER_H = PHONE_H + FRAME * 2;
const HERO = Math.round(PHONE_W * 0.62) + STATUS_BAR;
// The app's own map: Mapbox streets, with the public token the app loads at
// start (GET /config/keys; it is set in Settings). Without a token,
// OpenStreetMap: CARTO's free tiles, the app's own fallback, now answer
// "API key required".
const mapboxTiles = (token) =>
  `https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=${encodeURIComponent(token)}`;
const OSM_TILES = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';

let mapToken = null;
const loadMapToken = () => {
  mapToken ??= apiGet('/config/keys')
    .then((keys) => keys?.mapbox_access_token || '')
    .catch(() => { mapToken = null; return ''; });
  return mapToken;
};

const Icon = ({ name, size, color, style }) => (
  <span className="material-icons-round" style={{ fontSize: size, color, ...style }} aria-hidden="true">{name}</span>
);

/** A Phosphor icon (the app's phosphor_flutter): bold, fill or duotone. */
const Ph = ({ name, weight = 'bold', size, color, style }) => (
  <i className={`ph-${weight} ph-${name}`} style={{ fontSize: size, color, lineHeight: 1, flex: 'none', ...style }} aria-hidden="true" />
);

/** cityTourEst: a guide's time marked as an estimate, unless it says so. */
const ALREADY_EST = /\b(est|estimated|approx|about|around)\b|~/i;
const est = (time) => (ALREADY_EST.test(time) ? time : `${time} (est)`);

function Inline({ text }) {
  return inlineRuns(text).map((run, i) => {
    if (run.kind === 'bold') return <strong key={i}>{run.text}</strong>;
    if (run.kind === 'italic') return <em key={i}>{run.text}</em>;
    return <Fragment key={i}>{run.text}</Fragment>;
  });
}

/** ExperienceDescription (flutter_markdown with the app's style sheet). */
function AppMarkdown({ text }) {
  const blocks = parseBlocks(text);
  return (
    <div className="ctp-md">
      {blocks.map((b, i) => {
        if (b.type === 'heading') {
          return <div key={i} className={`ctp-md-h${b.level}`}><Inline text={b.text} /></div>;
        }
        if (b.type === 'divider') return <div key={i} className="ctp-md-hr" />;
        if (b.type === 'ul' || b.type === 'ol') {
          return (
            <div key={i} className="ctp-md-list">
              {b.items.map((t, j) => (
                <div key={j} className="ctp-md-li">
                  <span className="ctp-md-bullet">{b.type === 'ul' ? '•' : `${j + 1}.`}</span>
                  <span><Inline text={t} /></span>
                </div>
              ))}
            </div>
          );
        }
        return (
          <p key={i}>
            {b.lines.map((l, j) => <Fragment key={j}>{j > 0 && <br />}<Inline text={l} /></Fragment>)}
          </p>
        );
      })}
    </div>
  );
}

function StatusBar({ light }) {
  return (
    <div className={`ctp-status ${light ? 'light' : ''}`}>
      <span>9:41</span>
      <span className="ctp-status-icons">
        <Icon name="signal_cellular_alt" size={17} />
        <Icon name="wifi" size={17} />
        <Icon name="battery_full" size={17} style={{ transform: 'rotate(90deg)' }} />
      </span>
    </div>
  );
}

function Fact({ icon, text }) {
  return (
    <span className="ctp-fact">
      <Icon name={icon} size={15} color="#007A7C" />
      {text}
    </span>
  );
}

function facts(content) {
  const stops = allSteps(content).filter((s) => s.type === 'stop').length;
  const days = (content.days || []).length;
  return (
    <>
      {days > 1 && <Fact icon="calendar_today" text={`${days} days`} />}
      {stops > 0 && <Fact icon="place" text={stops === 1 ? '1 stop' : `${stops} stops`} />}
      {content.duration && <Fact icon="schedule" text={content.duration} />}
      {content.budget && <Fact icon="payments" text={content.budget} />}
    </>
  );
}

/** CityTourMap, as drawn inside the page: no panning, an "Open map" pill. */
function RouteMap({ stops, height, dashed = false }) {
  const el = useRef(null);
  const map = useRef(null);
  const layer = useRef(null);
  const pins = stops.filter((s) => s.lat != null && s.lng != null && s.lat !== '' && s.lng !== '');
  const key = JSON.stringify(pins.map((s) => [s.lat, s.lng, s.number]));

  useEffect(() => {
    if (!window.L || !el.current || map.current) return undefined;
    const m = window.L.map(el.current, {
      zoomControl: false, attributionControl: false, dragging: false, scrollWheelZoom: false,
      doubleClickZoom: false, boxZoom: false, keyboard: false, touchZoom: false,
    });
    map.current = m;
    loadMapToken().then((token) => {
      if (map.current !== m) return;
      window.L.tileLayer(token ? mapboxTiles(token) : OSM_TILES, { subdomains: 'abc', maxZoom: 19 }).addTo(m);
    });
    return () => {
      map.current.remove();
      map.current = null;
      layer.current = null;
    };
  }, []);

  useEffect(() => {
    const m = map.current;
    if (!m || !pins.length) return;
    if (layer.current) layer.current.remove();
    const group = window.L.layerGroup();
    const points = pins.map((s) => [Number(s.lat), Number(s.lng)]);
    if (points.length > 1) {
      window.L.polyline(points, { color: '#007A7C', opacity: 0.85, weight: 3, dashArray: dashed ? '8 6' : null }).addTo(group);
    }
    // The start on top, then each stop over the next, as the app draws them.
    // (Leaflet would otherwise stack the southern pin on top.)
    pins.forEach((s) => {
      window.L.marker([Number(s.lat), Number(s.lng)], {
        icon: window.L.divIcon({
          className: 'ctp-pin',
          html: `<span class="ctp-badge ${s.number === 1 ? 'start' : ''}">${escapeHtml(s.number)}</span>`,
          iconSize: [30, 30],
          iconAnchor: [15, 15],
        }),
        zIndexOffset: (pins.length - s.number) * 1000,
        interactive: false,
      }).addTo(group);
    });
    group.addTo(m);
    layer.current = group;
    m.invalidateSize();
    if (points.length > 1) m.fitBounds(points, { padding: [36, 36], maxZoom: 16 });
    else m.setView(points[0], 15);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  return (
    <div className="ctp-map" style={pins.length ? { height } : { display: 'none' }}>
      <div ref={el} className="ctp-map-canvas" />
      <span className="ctp-map-pill"><Icon name="fullscreen" size={16} /> Open map</span>
    </div>
  );
}

function LinkButton({ link, partners }) {
  if (link.kind === 'experience') {
    const pkg = (partners?.experiences || []).find((p) => p.id === link.package_id);
    if (!pkg) {
      return (
        <div className="ctp-missing">
          {link.package_id
            ? 'This Experience is not listed in the app now, so the app leaves this button out.'
            : 'Pick the Experience. Until then the app leaves this button out.'}
        </div>
      );
    }
    return (
      <div className="ctp-link">
        <span className="ctp-link-photo">
          {pkg.photo_url
            ? <img src={mediaUrl(pkg.photo_url)} alt="" />
            : <Icon name="sailing" size={22} color="#9E9E9E" />}
        </span>
        <span className="ctp-link-text">
          <span className="ctp-link-label">{link.label || pkg.title}</span>
          <span className="ctp-link-sub">{pkg.vendor_name}</span>
          {pkg.price_label && <span className="ctp-link-price">{pkg.price_label}</span>}
        </span>
        <span className="ctp-link-go"><Ph name="caret-right" size={15} color="#007A7C" /></span>
      </div>
    );
  }
  const affiliate = (partners?.affiliates || []).find((a) => a.key === link.partner);
  const name = affiliate?.name || link.partner;
  // The other partners' pages are made on save; only WeGoTrip needs a pick.
  if (link.partner === 'wegotrip' && !link.url) {
    return <div className="ctp-missing">Pick the WeGoTrip ticket. Until then the app leaves this button out.</div>;
  }
  return (
    <div className="ctp-link">
      <span className="ctp-link-logo"><img src={partnerLogo(link.partner)} alt="" /></span>
      <span className="ctp-link-text">
        <span className="ctp-link-label">{link.label || `Book on ${name}`}</span>
        <span className="ctp-link-sub">{name} · opens their site</span>
      </span>
      <span className="ctp-link-go"><Ph name="arrow-up-right" size={15} color="#007A7C" /></span>
    </div>
  );
}

/** "TICKETS & TOURS" and a step's partner buttons. */
function Links({ links, partners }) {
  if (!links?.length) return null;
  return (
    <div className="ctp-links">
      <div className="ctp-links-head">TICKETS &amp; TOURS</div>
      {links.map((l) => <LinkButton key={l.id} link={l} partners={partners} />)}
    </div>
  );
}

/** CityTourTick before a trip: a stop's number (the start teal), or a ride's icon. */
function Tick({ step, number, size }) {
  if (step.type === 'stop') {
    return (
      <span className={`ctp-tick ${number === 1 ? 'start' : ''}`} style={{ width: size, height: size, fontSize: size * 0.42 }}>
        {number}
      </span>
    );
  }
  const icon = step.type === 'break' ? 'restaurant' : modeOf(step.mode).icon;
  return (
    <span className="ctp-tick leg" style={{ width: size, height: size }}>
      <Icon name={icon} size={size * 0.56} color={step.type === 'break' ? '#92400e' : '#0f172a'} />
    </span>
  );
}

/** The guide's "Closure / Access" note, in an amber box. */
const NoteBox = ({ text }) => (
  <div className="ctp-notebox"><Ph name="info" weight="duotone" size={15} color="#D97706" /><span>{text}</span></div>
);

/** The stop's own page: "More info · site" (the app's _MoreInfo). */
function MoreInfo({ url }) {
  const full = /^https?:\/\//i.test(url) ? url : `https://${url}`;
  let site;
  try {
    site = new URL(full).hostname.replace(/^www\./, '');
  } catch {
    site = '';
  }
  return (
    <a className="ctp-moreinfo" href={full} target="_blank" rel="noopener noreferrer">
      <Icon name="language" size={17} color="#007A7C" />
      <b>More info</b>
      <span>{site}</span>
      <Icon name="open_in_new" size={16} color="#64748B" />
    </a>
  );
}

/** CityTourStopCard before a trip: open, the name on the photo; its time is the chip's estimate, no clock. */
function StopCard({ step, number, caption, partners }) {
  const badge = caption && <span className="ctp-sc-badge">{caption}</span>;
  const parts = [
    (step.time_here || step.price) && (
      <div key="chips" className="ctp-chips">
        {step.time_here && (
          <span className="ctp-chip purple"><Ph name="hourglass-medium" weight="duotone" size={15} color="#7C3AED" />{est(step.time_here)}</span>
        )}
        {step.price && (
          <span className="ctp-chip green"><Ph name="ticket" weight="duotone" size={15} color="#15803D" />{step.price}</span>
        )}
      </div>
    ),
    step.access_note && <NoteBox key="note" text={step.access_note} />,
    step.body_md && <AppMarkdown key="md" text={step.body_md} />,
    step.links?.length > 0 && <Links key="links" links={step.links} partners={partners} />,
    step.website?.trim() && <MoreInfo key="web" url={step.website.trim()} />,
  ].filter(Boolean);
  return (
    <div className="ctp-sc">
      {step.photo_url ? (
        <div className="ctp-sc-photo">
          <img src={mediaUrl(step.photo_url)} alt="" />
          <div className="ctp-sc-shade" />
          {badge && <span className="ctp-sc-badge-at">{badge}</span>}
          <div className="ctp-sc-foot">
            <Tick step={step} number={number} size={40} />
            <div>
              <div className="ctp-sc-name">{step.name}</div>
            </div>
          </div>
        </div>
      ) : (
        <div className="ctp-sc-head">
          <Tick step={step} number={number} size={40} />
          <div>
            {badge && <div style={{ marginBottom: 6 }}>{badge}</div>}
            <div className="ctp-sc-name dark">{step.name}</div>
          </div>
        </div>
      )}
      {parts.length > 0
        ? <div className="ctp-sc-body" style={{ paddingTop: step.photo_url ? 14 : 0 }}>{parts}</div>
        : <div style={{ height: 4 }} />}
    </div>
  );
}

/** CityTourLegPill: a walk or ride as a dark navy pill on a dashed line (a break amber); a click opens it. */
function LegPill({ step, from, to, partners }) {
  const [open, setOpen] = useState(false);
  const isBreak = step.type === 'break';
  const title = isBreak ? (step.title || 'Break') : modeOf(step.mode).label;
  const directions = isBreak ? '' : step.title;
  const extras = [step.duration && est(step.duration), step.cost, !open && directions].filter(Boolean);
  // The app draws the street route; this preview only joins the two stops.
  const hasMap = step.type === 'move' && to && hasPin(to);
  const more = Boolean(hasMap || directions || step.access_note || step.body_md || step.links?.length);
  return (
    <div>
      <div className="ctp-dash" />
      <div className="ctp-leg-row">
        <div className={`ctp-leg ${isBreak ? 'break' : ''} ${more ? 'more' : ''}`} onClick={() => more && setOpen(!open)}>
          <Tick step={step} size={24} />
          <span className="ctp-leg-text">
            <strong>{title}</strong>{extras.length > 0 && <span> · {extras.join(' · ')}</span>}
          </span>
          {more && <Ph name={open ? 'caret-up' : 'caret-down'} size={12} color="rgba(255,255,255,0.6)" />}
        </div>
      </div>
      {open && more && (
        <div className="ctp-leg-card">
          {directions && <div className="ctp-leg-dir">{directions}</div>}
          {hasMap && <RouteMap stops={from && hasPin(from) ? [from, to] : [to]} height={170} dashed />}
          {step.access_note && <NoteBox text={step.access_note} />}
          {step.body_md && <AppMarkdown text={step.body_md} />}
          <Links links={step.links} partners={partners} />
        </div>
      )}
      <div className="ctp-dash" />
    </div>
  );
}

const hasPin = (s) => s.lat != null && s.lng != null && s.lat !== '' && s.lng !== '';

/** One day's route: its map, then a card for each stop and a pill for each leg. */
function DayRoute({ day, partners }) {
  const steps = day.steps || [];
  const numbers = stopNumbers(steps);
  const stops = steps.filter((s) => s.type === 'stop').map((s) => ({ ...s, number: numbers[s.id] }));
  const lastStopId = stops.length > 1 ? stops[stops.length - 1].id : null;
  // The nearest stop before (by -1) or after (by 1) step i, for a ride's map.
  const stopNear = (i, by) => {
    for (let j = i + by; j >= 0 && j < steps.length; j += by) {
      if (steps[j].type === 'stop') return { ...steps[j], number: numbers[steps[j].id] };
    }
    return null;
  };
  return (
    <>
      <RouteMap key={day.id} stops={stops} />
      {stops.some(hasPin) && <div style={{ height: 14 }} />}
      {steps.map((s, i) => (
        <Fragment key={s.id}>
          {i > 0 && s.type === 'stop' && steps[i - 1].type === 'stop' && <div style={{ height: 12 }} />}
          {s.type === 'stop'
            ? (
              <StopCard
                step={s} number={numbers[s.id]} partners={partners}
                caption={i === 0 ? 'START HERE' : s.id === lastStopId ? 'LAST STOP' : null}
              />
            )
            : <LegPill step={s} from={stopNear(i, -1)} to={stopNear(i, 1)} partners={partners} />}
        </Fragment>
      ))}
    </>
  );
}

/** A small grey heading with a teal link: "YOUR PLAN · 2 DAYS   Change". */
function Heading({ text, link, icon, onClick }) {
  return (
    <div className="ctp-heading">
      <span>{text}</span>
      {link && (
        <span className="ctp-heading-link" onClick={onClick}>
          {icon && <Ph name={icon} size={13} color="#007A7C" />}{link}
        </span>
      )}
    </div>
  );
}

const dayLine = (day) => {
  const plan = dayPlan(day);
  const places = (day.steps || []).filter((s) => s.type === 'stop').length;
  return [plan.start !== null ? `${formatClock(plan.start)} – ${formatClock(plan.end)}` : '',
    `${places} place${places === 1 ? '' : 's'}`].filter(Boolean).join(' · ');
};

/**
 * CityTourPlanPicker, two ways: "Day based" takes the first N days; "Place
 * based" ticks each day's set of places. The way picked greys the other out.
 */
function Planner({ days, onShow }) {
  const [way, setWay] = useState(null);
  const [count, setCount] = useState(0);
  const [picked, setPicked] = useState([]);
  const chosen = way === 'days'
    ? days.slice(0, count).map((d) => d.id)
    : way === 'places' ? days.map((d) => d.id).filter((id) => picked.includes(id)) : [];
  const toggle = (id) => setPicked(picked.includes(id) ? picked.filter((x) => x !== id) : [...picked, id]);
  const wayButton = (key, icon, label) => (
    <div
      className={`ctp-way ${way === key ? 'on' : ''} ${way && way !== key ? 'off' : ''}`}
      onClick={() => way !== key && setWay(key)}
    >
      <Icon name={icon} size={22} color={way === key ? '#fff' : way ? '#9E9E9E' : '#007A7C'} />
      <span>{label}</span>
    </div>
  );
  return (
    <div className="ctp-planner">
      <div className="ctp-caption">PLAN YOUR DAYS</div>
      <div className="ctp-planner-title">How do you want to plan?</div>
      <div className="ctp-ways">
        {wayButton('days', 'calendar_today', 'Day based')}
        {wayButton('places', 'place', 'Place based')}
      </div>
      {way === 'days' && (
        <>
          <div className="ctp-planner-or">How many days do you have?</div>
          <div className="ctp-daychips">
            {days.map((d, i) => (
              <span key={d.id} className={`ctp-daychip ${count === i + 1 ? 'on' : ''}`} onClick={() => setCount(i + 1)}>
                {i + 1}
              </span>
            ))}
          </div>
        </>
      )}
      {way === 'places' && (
        <>
          <div className="ctp-planner-or">Pick the sets of places you want</div>
          <div>
            {days.map((d) => (
              <div key={d.id} className="ctp-daypick" onClick={() => toggle(d.id)}>
                <Icon
                  name={picked.includes(d.id) ? 'check_box' : 'check_box_outline_blank'} size={22}
                  color={picked.includes(d.id) ? '#007A7C' : '#9E9E9E'}
                />
                <span>
                  <strong>{d.title || 'Places to see'}</strong>
                  <span>{dayLine(d)}</span>
                </span>
              </div>
            ))}
          </div>
        </>
      )}
      {way && (
        <div className={`ctp-planner-btn ${chosen.length ? '' : 'off'}`} onClick={() => chosen.length && onShow(chosen)}>
          {chosen.length ? `Show my ${chosen.length}-day plan` : way === 'days' ? 'Pick your days' : 'Pick your places'}
        </div>
      )}
    </div>
  );
}

/** The cover photo, shaded at the top for the status bar and the back button. */
function Hero({ content }) {
  return (
    <div className="ctp-hero" style={{ height: HERO }}>
      {content.cover_url
        ? <img src={mediaUrl(content.cover_url)} alt="" />
        : <div className="ctp-hero-empty">Cover photo</div>}
      <div className="ctp-hero-shade" />
      <StatusBar light />
      <span className="ctp-glass"><Ph name="arrow-left" size={20} color="#fff" /></span>
    </div>
  );
}

function GuidePage({ content, partners, activeDayId }) {
  const days = content.days || [];
  const ids = days.map((d) => d.id);
  const several = days.length > 1;
  // The traveller's plan (day ids) and the day on screen, as in the app. The
  // editor's day being worked on (activeDayId) is brought into view.
  const [plan, setPlan] = useState(null);
  const [tab, setTab] = useState(null);
  const [seenActive, setSeenActive] = useState(activeDayId);
  if (activeDayId !== seenActive) {
    setSeenActive(activeDayId);
    if (activeDayId && ids.includes(activeDayId)) {
      if (!plan || !plan.includes(activeDayId)) setPlan(ids);
      setTab(activeDayId);
    }
  }
  const planDays = (plan || []).map((id) => days.find((d) => d.id === id)).filter(Boolean);
  const shown = several
    ? planDays.find((d) => d.id === tab) || planDays[0]
    : days[0];
  const shownNumber = shown ? planDays.indexOf(shown) + 1 : 1;
  const place = [content.city, content.country].filter(Boolean).join(' · ');
  return (
    <div className="ctp-page guide">
      <Hero content={content} />
      <div className="ctp-head">
        {place && <div className="ctp-place">{place.toUpperCase()}</div>}
        <div className="ctp-title">{content.title || 'Title'}</div>
        {content.summary && <div className="ctp-summary">{content.summary}</div>}
      </div>
      <div className="ctp-body">
        {content.intro_md && <div style={{ marginBottom: 20 }}><AppMarkdown text={content.intro_md} /></div>}
        {!several && shown && (
          <>
            <Heading text="THE ROUTE" />
            <div style={{ height: 12 }} />
            <DayRoute day={shown} partners={partners} />
          </>
        )}
        {several && (!shown ? (
          <Planner days={days} onShow={(chosen) => { setPlan(chosen); setTab(chosen[0]); }} />
        ) : (
          <>
            <Heading
              text={`YOUR PLAN · ${planDays.length} DAY${planDays.length === 1 ? '' : 'S'}`}
              link="Change" icon="sliders-horizontal" onClick={() => setPlan(null)}
            />
            <div className="ctp-daypills">
              {planDays.map((d, i) => (
                <span
                  key={d.id}
                  className={`ctp-daypill ${d.id === shown.id ? 'on' : ''}`}
                  onClick={() => setTab(d.id)}
                >
                  Day {i + 1}
                </span>
              ))}
            </div>
            {/* No "DAY N · STOPS" heading, as in the app (it added to the crowd). */}
            <div style={{ height: 14 }} />
            <DayRoute day={shown} partners={partners} />
          </>
        ))}
      </div>
      {shown && (shown.steps || []).length > 0 && (
        // CityTourTripBar before a trip starts (the page's bottomNavigationBar).
        <div className="ctp-tripbar">
          <div className="ctp-tripbar-note">Plans your times from now. Tap each stop’s circle as you finish it.</div>
          <div className="ctp-trip-btn">
            <Ph name="play" weight="fill" size={18} color="#fff" />{several ? `Start Day ${shownNumber}` : 'Start trip'}
          </div>
        </div>
      )}
    </div>
  );
}

/** CityTourListPage with this guide's card (CityTourCardTile). */
function ListPage({ content }) {
  return (
    <div className="ctp-page">
      <StatusBar />
      <div className="ctp-appbar">
        <Icon name="arrow_back" size={24} color="#000" />
        <div>
          <div className="ctp-appbar-title">{content.city || 'City'}</div>
          <div className="ctp-appbar-sub">{[content.country, '2 guides'].filter(Boolean).join(' · ')}</div>
        </div>
      </div>
      <div className="ctp-list">
        <div className="ctp-card-cover">
          {content.cover_url && <img src={mediaUrl(content.cover_url)} alt="" />}
        </div>
        <div className="ctp-card-title">{content.title || 'Title'}</div>
        {content.summary && <div className="ctp-card-summary">{content.summary}</div>}
        <div className="ctp-facts" style={{ marginTop: 8 }}>{facts(content)}</div>
      </div>
    </div>
  );
}

/**
 * The phone is always laid out at its real size; on a short window or a narrow
 * column it is shrunk as a whole (never stretched) so all of it shows at once.
 */
function useFitScale(root, fit) {
  const [scale, setScale] = useState(1);
  useEffect(() => {
    const measure = () => {
      if (!root.current || !fit.current) return;
      const box = root.current.getBoundingClientRect();
      const phone = fit.current.getBoundingClientRect();
      // the tabs above the phone and the note below it
      const around = (phone.top - box.top) + (box.bottom - phone.bottom);
      const header = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--header-h')) || 0;
      const roomH = window.innerHeight - header - 32 - around;
      setScale(Math.min(1, root.current.clientWidth / OUTER_W, roomH / OUTER_H));
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(root.current);
    window.addEventListener('resize', measure);
    return () => {
      observer.disconnect();
      window.removeEventListener('resize', measure);
    };
  }, [root, fit]);
  return scale;
}

/**
 * A phone showing the guide as travellers will see it, redrawn as the content
 * changes. "Guide page" is the guide itself; "In a list" is its card where a
 * city has more than one guide.
 */
export default function CityTourPreview({ content, partners, activeDayId = null, tab: initialTab = 'page' }) {
  const [tab, setTab] = useState(initialTab);
  const root = useRef(null);
  const fit = useRef(null);
  const scale = useFitScale(root, fit);
  return (
    <div className="ctp" ref={root}>
      <div className="ctp-tabs">
        <div className="seg">
          <button type="button" className={`seg-btn ${tab === 'page' ? 'active' : ''}`} onClick={() => setTab('page')}>
            Guide page
          </button>
          <button type="button" className={`seg-btn ${tab === 'list' ? 'active' : ''}`} onClick={() => setTab('list')}>
            In a list
          </button>
        </div>
      </div>
      <div className="ctp-fit" ref={fit} style={{ width: OUTER_W * scale, height: OUTER_H * scale }}>
        <div className="ctp-phone" style={{ transform: `scale(${scale})` }}>
          <div className="ctp-screen">
            {tab === 'page'
              ? <GuidePage content={content} partners={partners} activeDayId={activeDayId} />
              : <ListPage content={content} />}
          </div>
          <span className="ctp-island" />
        </div>
      </div>
      <div className="ctp-note">
        As in the app.
      </div>
    </div>
  );
}
