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

const StopBadge = ({ number }) => (
  <span className={`ctp-badge ${number === 1 ? 'start' : ''}`}>{number}</span>
);

/** CityTourMap, as drawn inside the page: no panning, an "Open map" pill. */
function RouteMap({ stops }) {
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
      window.L.polyline(points, { color: '#007A7C', opacity: 0.85, weight: 3 }).addTo(group);
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
    <div className="ctp-map" style={pins.length ? undefined : { display: 'none' }}>
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
        <Icon name="chevron_right" size={22} color="#9E9E9E" />
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
      <Icon name="open_in_new" size={18} color="#9E9E9E" />
    </div>
  );
}

function Links({ links, partners, gap }) {
  if (!links?.length) return null;
  return (
    <div className="ctp-links" style={{ marginTop: gap }}>
      {links.map((l) => <LinkButton key={l.id} link={l} partners={partners} />)}
    </div>
  );
}

/** The planned "9:00 AM – 11:45 AM" above a step (CityTourStepTile._time). */
function PlannedTime({ time, stop }) {
  if (!time) return null;
  return (
    <div className="ctp-time" style={{ paddingTop: stop ? 2 : 5, paddingBottom: stop ? 2 : 0 }}>
      <Icon name="schedule" size={14} color="#9E9E9E" />
      {formatClock(time[0])} – {formatClock(time[1])}
    </div>
  );
}

function AccessNote({ text }) {
  if (!text) return null;
  return (
    <div className="ctp-access">
      <Icon name="info_outline" size={14} color="#9E9E9E" />
      <span>{text}</span>
    </div>
  );
}

function Step({ step, number, isFirst, isLast, isLastStop, partners, time }) {
  const line = !(isFirst && isLast) && (
    <span
      className="ctp-rail"
      style={isLast ? { top: isFirst ? 14 : 0, height: 14 } : { top: isFirst ? 14 : 0, bottom: 0 }}
    />
  );
  if (step.type === 'break') {
    return (
      <div className="ctp-step" style={{ paddingBottom: isLast ? 0 : 22 }}>
        {line}
        <span className="ctp-mode"><Icon name="restaurant" size={15} color="#545454" /></span>
        <div className="ctp-step-body">
          <PlannedTime time={time} />
          <div style={{ paddingTop: 5 }}>
            <div className="ctp-move-line">
              <strong>{step.title || 'Break'}</strong>
              {step.duration && <span> · {step.duration}</span>}
            </div>
            <AccessNote text={step.access_note} />
            {step.body_md && <div style={{ marginTop: 8 }}><AppMarkdown text={step.body_md} /></div>}
            <Links links={step.links} partners={partners} gap={10} />
          </div>
        </div>
      </div>
    );
  }
  if (step.type === 'stop') {
    const caption = isFirst ? 'START HERE' : isLastStop ? 'LAST STOP' : null;
    return (
      <div className="ctp-step" style={{ paddingBottom: isLast ? 0 : 22 }}>
        {line}
        <StopBadge number={number} />
        <div className="ctp-step-body">
          <PlannedTime time={time} stop />
          <div style={{ paddingTop: 2 }}>
          {caption && <div className="ctp-caption">{caption}</div>}
          <div className="ctp-stop-name">{step.name}</div>
          {(step.time_here || step.price) && (
            <div className="ctp-meta">
              {step.time_here && <span><Icon name="hourglass_bottom" size={14} color="#9E9E9E" />{step.time_here}</span>}
              {step.price && <span><Icon name="confirmation_number" size={14} color="#9E9E9E" />{step.price}</span>}
            </div>
          )}
          <AccessNote text={step.access_note} />
          {step.photo_url && <img className="ctp-stop-photo" src={mediaUrl(step.photo_url)} alt="" />}
          {step.body_md && <div style={{ marginTop: 10 }}><AppMarkdown text={step.body_md} /></div>}
          <Links links={step.links} partners={partners} gap={12} />
          </div>
        </div>
      </div>
    );
  }
  const mode = modeOf(step.mode);
  const extras = [step.duration, step.cost].filter(Boolean);
  return (
    <div className="ctp-step" style={{ paddingBottom: isLast ? 0 : 22 }}>
      {line}
      <span className="ctp-mode"><Icon name={mode.icon} size={15} color="#545454" /></span>
      <div className="ctp-step-body">
        <PlannedTime time={time} />
        <div style={{ paddingTop: 5 }}>
          <div className="ctp-move-line">
            <strong>{mode.label}</strong>
            {extras.length > 0 && <span> · {extras.join(' · ')}</span>}
          </div>
          {step.title && <div className="ctp-move-dir">{step.title}</div>}
          <AccessNote text={step.access_note} />
          {step.body_md && <div style={{ marginTop: 8 }}><AppMarkdown text={step.body_md} /></div>}
          <Links links={step.links} partners={partners} gap={10} />
        </div>
      </div>
    </div>
  );
}

/** One day's route: its map, then each step with its planned time. */
function DayRoute({ day, partners }) {
  const steps = day.steps || [];
  const numbers = stopNumbers(steps);
  const plan = dayPlan(day);
  const stops = steps.filter((s) => s.type === 'stop').map((s) => ({ ...s, number: numbers[s.id] }));
  const lastStopId = stops.length > 1 ? stops[stops.length - 1].id : null;
  return (
    <>
      <RouteMap key={day.id} stops={stops} />
      <div style={{ height: 18 }} />
      {steps.map((s, i) => (
        <Step
          key={s.id} step={s} number={numbers[s.id]} partners={partners} time={plan.times[s.id]}
          isFirst={i === 0} isLast={i === steps.length - 1} isLastStop={s.id === lastStopId}
        />
      ))}
    </>
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
            {days.map((d, i) => (
              <div key={d.id} className="ctp-daypick" onClick={() => toggle(d.id)}>
                <Icon
                  name={picked.includes(d.id) ? 'check_box' : 'check_box_outline_blank'} size={22}
                  color={picked.includes(d.id) ? '#007A7C' : '#9E9E9E'}
                />
                <span>
                  <strong>Day {i + 1} · {d.title || 'Places to see'}</strong>
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
    <div className="ctp-page">
      <div className="ctp-hero" style={{ height: HERO }}>
        {content.cover_url
          ? <img src={mediaUrl(content.cover_url)} alt="" />
          : <div className="ctp-hero-empty">Cover photo</div>}
        <StatusBar light />
        <span className="ctp-back"><Icon name="arrow_back" size={20} color="#000" /></span>
      </div>
      <div className="ctp-head">
        {place && <div className="ctp-place">{place.toUpperCase()}</div>}
        <div className="ctp-title">{content.title || 'Title'}</div>
        {content.summary && <div className="ctp-summary">{content.summary}</div>}
        <div className="ctp-facts">{facts(content)}</div>
      </div>
      <div className="ctp-body">
        {!several && shown && (
          <>
            {content.intro_md && <div style={{ marginBottom: 20 }}><AppMarkdown text={content.intro_md} /></div>}
            <div className="ctp-route-title" style={{ marginTop: 0 }}>The route</div>
            <DayRoute day={shown} partners={partners} />
          </>
        )}
        {several && (
          <>
            {content.intro_md && <div style={{ marginBottom: 20 }}><AppMarkdown text={content.intro_md} /></div>}
            {!shown ? (
              <Planner days={days} onShow={(ids) => { setPlan(ids); setTab(ids[0]); }} />
            ) : (
              <>
                <div className="ctp-plan-head">
                  <span className="ctp-caption">YOUR PLAN · {planDays.length} DAY{planDays.length === 1 ? '' : 'S'}</span>
                  <span className="ctp-plan-change" onClick={() => setPlan(null)}>Change</span>
                </div>
                <div className="ctp-daytabs">
                  {planDays.map((d, i) => (
                    <span key={d.id} className={`ctp-daytab ${d.id === shown.id ? 'on' : ''}`} onClick={() => setTab(d.id)}>
                      Day {i + 1}
                    </span>
                  ))}
                </div>
                <div className="ctp-day-title">{shown.title || `Day ${shownNumber}`}</div>
                <div className="ctp-day-meta">{dayLine(shown)}</div>
                <div style={{ height: 14 }} />
                <DayRoute day={shown} partners={partners} />
              </>
            )}
          </>
        )}
      </div>
      {shown && (shown.steps || []).length > 0 && (
        // CityTourTripBar before a trip starts (the page's bottomNavigationBar).
        <div className="ctp-tripbar">
          <div className="ctp-tripbar-note">Plans your times from now and reminds you at each stop.</div>
          <div className="ctp-trip-btn">
            <Icon name="play_arrow" size={22} color="#fff" />{several ? `Start Day ${shownNumber}` : 'Start trip'}
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
