import { Fragment, useEffect, useRef, useState } from 'react';
import { mediaUrl } from '../api';
import { inlineRuns, parseBlocks } from '../descriptionFormat';
import { escapeHtml } from '../places';
import { modeOf, partnerLogo, stopNumbers } from '../cityTours';

// The guide as the app draws it, at the app's own sizes: a copy of
// nexaround_app/lib/features/city_tours/ (city_tour_page.dart and
// city_tour_widgets.dart). Change one, change the other.

const PHONE_W = 390;
const STATUS_BAR = 47;
const HERO = Math.round(PHONE_W * 0.62) + STATUS_BAR;
const TILES = 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';

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
  const stops = (content.steps || []).filter((s) => s.type === 'stop').length;
  return (
    <>
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
    map.current = window.L.map(el.current, {
      zoomControl: false, attributionControl: false, dragging: false, scrollWheelZoom: false,
      doubleClickZoom: false, boxZoom: false, keyboard: false, touchZoom: false,
    });
    window.L.tileLayer(TILES, { subdomains: 'abcd', maxZoom: 19 }).addTo(map.current);
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
  if (!link.url) {
    return <div className="ctp-missing">Paste the {name} page. Until then the app leaves this button out.</div>;
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

function Step({ step, number, isFirst, isLast, isLastStop, partners }) {
  const line = !(isFirst && isLast) && (
    <span
      className="ctp-rail"
      style={isLast ? { top: isFirst ? 14 : 0, height: 14 } : { top: isFirst ? 14 : 0, bottom: 0 }}
    />
  );
  if (step.type === 'stop') {
    const caption = isFirst ? 'START HERE' : isLastStop ? 'LAST STOP' : null;
    return (
      <div className="ctp-step" style={{ paddingBottom: isLast ? 0 : 22 }}>
        {line}
        <StopBadge number={number} />
        <div className="ctp-step-body" style={{ paddingTop: 2 }}>
          {caption && <div className="ctp-caption">{caption}</div>}
          <div className="ctp-stop-name">{step.name}</div>
          {(step.time_here || step.price) && (
            <div className="ctp-meta">
              {step.time_here && <span><Icon name="hourglass_bottom" size={14} color="#9E9E9E" />{step.time_here}</span>}
              {step.price && <span><Icon name="confirmation_number" size={14} color="#9E9E9E" />{step.price}</span>}
            </div>
          )}
          {step.photo_url && <img className="ctp-stop-photo" src={mediaUrl(step.photo_url)} alt="" />}
          {step.body_md && <div style={{ marginTop: 10 }}><AppMarkdown text={step.body_md} /></div>}
          <Links links={step.links} partners={partners} gap={12} />
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
      <div className="ctp-step-body" style={{ paddingTop: 5 }}>
        <div className="ctp-move-line">
          <strong>{mode.label}</strong>
          {extras.length > 0 && <span> · {extras.join(' · ')}</span>}
        </div>
        {step.title && <div className="ctp-move-dir">{step.title}</div>}
        {step.body_md && <div style={{ marginTop: 8 }}><AppMarkdown text={step.body_md} /></div>}
        <Links links={step.links} partners={partners} gap={10} />
      </div>
    </div>
  );
}

function GuidePage({ content, partners }) {
  const steps = content.steps || [];
  const numbers = stopNumbers(steps);
  const stops = steps.filter((s) => s.type === 'stop').map((s) => ({ ...s, number: numbers[s.id] }));
  const lastStopId = stops.length > 1 ? stops[stops.length - 1].id : null;
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
        <RouteMap stops={stops} />
        {content.intro_md && <div style={{ marginTop: 20 }}><AppMarkdown text={content.intro_md} /></div>}
        <div className="ctp-route-title">The route</div>
        {steps.map((s, i) => (
          <Step
            key={s.id} step={s} number={numbers[s.id]} partners={partners}
            isFirst={i === 0} isLast={i === steps.length - 1} isLastStop={s.id === lastStopId}
          />
        ))}
      </div>
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
 * A phone showing the guide as travellers will see it, redrawn as the content
 * changes. "Guide page" is the guide itself; "In a list" is its card where a
 * city has more than one guide.
 */
export default function CityTourPreview({ content, partners, tab: initialTab = 'page' }) {
  const [tab, setTab] = useState(initialTab);
  return (
    <div className="ctp">
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
      <div className="ctp-phone">
        <div className="ctp-screen">
          {tab === 'page'
            ? <GuidePage content={content} partners={partners} />
            : <ListPage content={content} />}
        </div>
      </div>
      <div className="ctp-note">
        As in the app. The map tiles may look slightly different; the pins and route are the same.
      </div>
    </div>
  );
}
