import { useEffect, useRef, useState } from 'react';
import { mediaUrl } from '../api';
import { DURATIONS, TOUR_LABELS, categoryColor, categoryIcon, tourOrder } from '../museums';

// The app's museum guide page (nexaround_app/lib/features/planning/
// presentation/pages/museum_guide_page.dart), redrawn at its own sizes in
// the same iPhone frame as the City Guides preview (.ctp-* styles).
const PHONE_W = 402;
const PHONE_H = 874;
const FRAME = 10;
const OUTER_W = PHONE_W + FRAME * 2;
const OUTER_H = PHONE_H + FRAME * 2;

const Icon = ({ name, size, color, style }) => (
  <span className="material-icons-round" style={{ fontSize: size, color, ...style }} aria-hidden="true">{name}</span>
);

function StatusBar() {
  return (
    <div className="ctp-status light">
      <span>9:41</span>
      <span className="ctp-status-icons">
        <Icon name="signal_cellular_alt" size={17} />
        <Icon name="wifi" size={17} />
        <Icon name="battery_full" size={17} style={{ transform: 'rotate(90deg)' }} />
      </span>
    </div>
  );
}

/** Shrinks the phone as a whole to fit the column and the window. */
function useFitScale(root, fit) {
  const [scale, setScale] = useState(1);
  useEffect(() => {
    const measure = () => {
      if (!root.current || !fit.current) return;
      const box = root.current.getBoundingClientRect();
      const phone = fit.current.getBoundingClientRect();
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

/** Items of one tour grouped by building, in the order each building first comes up. */
function byBuilding(items) {
  const groups = [];
  items.forEach((item, i) => {
    const last = groups.find((g) => g.building === item.building);
    const entry = { item, stop: i + 1 };
    if (last) last.items.push(entry);
    else groups.push({ building: item.building, items: [entry] });
  });
  return groups;
}

function ItemRow({ item, stop, first, last }) {
  const color = categoryColor(item.category);
  return (
    <div className="mup-item">
      <div className="mup-rail">
        <span className="mup-line" style={{ background: first ? 'transparent' : `${color}4d` }} />
        <span className="mup-dot" style={{ background: color, boxShadow: `0 0 6px ${color}4d` }} />
        <span className="mup-line" style={{ background: last ? 'transparent' : `${color}4d` }} />
      </div>
      <div className="mup-card">
        <div className="mup-card-top">
          <span className="mup-chip" style={{ background: `${color}1a`, color }}>
            <Icon name={categoryIcon(item.category)} size={12} color={color} /> {item.category || 'Category'}
          </span>
          <span className="mup-stop">#{stop}</span>
        </div>
        <div className="mup-name">{item.must_see_item || 'Must-see item'}</div>
        {item.artist && <div className="mup-artist">{item.artist}</div>}
        <div className="mup-room"><Icon name="room" size={14} /> <span>{item.room_gallery || 'Room / gallery'}</span></div>
        {item.description && <div className="mup-desc">{item.description}</div>}
      </div>
    </div>
  );
}

/**
 * A phone showing the museum's guide page as travellers will see it: the
 * photo header, the tour picker, hours and website, then the chosen tour's
 * stops by building. `tour` picks the tour shown first.
 */
export default function MuseumPreview({ museum, items, photoUrl, tour }) {
  const root = useRef(null);
  const fit = useRef(null);
  const scale = useFitScale(root, fit);
  const tours = DURATIONS.filter((d) => items.some((item) => item[`included_${d}`]));
  // The editor's tab leads; the phone's own chips can look at another tour
  // until the editor switches tab again.
  const [picked, setPicked] = useState(null); // { tour, d }
  const own = picked && picked.tour === tour ? picked.d : null;
  const shown = tours.includes(own) ? own
    : tours.includes(tour) ? tour
      : tours.includes('1d') ? '1d' : tours[0];
  const stops = shown ? tourOrder(items, shown) : [];
  const groups = byBuilding(stops);
  const hours = (museum.opening_hours || '').trim() || '9:00 AM – 6:00 PM';

  return (
    <div className="ctp" ref={root}>
      <div className="ctp-fit" ref={fit} style={{ width: OUTER_W * scale, height: OUTER_H * scale }}>
        <div className="ctp-phone" style={{ transform: `scale(${scale})` }}>
          <div className="ctp-screen">
            <div className="ctp-page mup-page">
              <div className="mup-hero">
                {photoUrl ? <img src={mediaUrl(photoUrl)} alt="" /> : <Icon name="museum" size={80} color="rgba(255,255,255,0.38)" />}
                <div className="mup-scrim" />
                <div className="mup-top"><StatusBar /></div>
                <span className="mup-back"><Icon name="arrow_back_ios_new" size={16} color="#fff" /></span>
                <div className="mup-place">
                  <Icon name="place" size={14} /> {museum.city || 'City'}, {museum.country || 'Country'}
                </div>
                <div className="mup-title">{museum.name || 'Museum name'}</div>
              </div>

              {tours.length > 0 && (
                <div className="mup-tours">
                  {tours.map((d) => (
                    <button key={d} type="button" className={`mup-tour ${d === shown ? 'active' : ''}`} onClick={() => setPicked({ tour, d })}>
                      {TOUR_LABELS[d]}
                    </button>
                  ))}
                </div>
              )}

              <div className="mup-tickets">
                <span className="mup-tickets-icon"><Icon name="confirmation_number" size={22} color="#007A7C" /></span>
                <span className="mup-tickets-text">
                  <strong>Skip-the-Line Tickets</strong>
                  <span>Book fast-track entry &amp; guided tours</span>
                </span>
                <Icon name="arrow_forward_ios" size={16} color="rgba(255,255,255,0.38)" />
              </div>

              <div className="mup-stats">
                <div className="mup-stat-row">
                  <span className="mup-stat"><Icon name="visibility" size={14} /> {stops.length} Must-See</span>
                  <span className="mup-stat mup-stat-wide"><Icon name="access_time_filled" size={14} /> <span>{hours}</span></span>
                </div>
                <span className="mup-site"><Icon name="language" size={16} color="#007A7C" /> Visit official website</span>
              </div>

              {stops.length === 0 ? (
                <div className="mup-empty">
                  <Icon name="hourglass_top" size={28} color="#D97706" />
                  <strong>Itinerary Coming Soon</strong>
                  <span>A curated masterpiece itinerary for {museum.name || 'this museum'} is currently being crafted and will be available in a future update.</span>
                </div>
              ) : groups.map((g) => (
                <div key={g.building}>
                  <div className="mup-building">
                    <span className="mup-building-icon"><Icon name="domain" size={18} color="#fff" /></span>
                    <span>
                      <strong>{g.building}</strong>
                      <span>{g.items.length} stops</span>
                    </span>
                  </div>
                  {g.items.map(({ item, stop }, i) => (
                    <ItemRow key={item.key} item={item} stop={stop} first={i === 0} last={i === g.items.length - 1} />
                  ))}
                </div>
              ))}
              <div style={{ height: 40 }} />
            </div>
          </div>
          <span className="ctp-island" />
        </div>
      </div>
      <div className="ctp-note">
        As in the app. The hours chip shows “9:00 AM – 6:00 PM” until hours are entered.
      </div>
    </div>
  );
}
