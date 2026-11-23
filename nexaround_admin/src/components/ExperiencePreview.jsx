import { useState } from 'react';
import { mediaUrl } from '../api';
import PhoneFrame, { AppMarkdown, MIcon, StatusBar } from './PhoneFrame';

// An Experience package as the app draws it (nexaround_app/lib/features/
// experiences): its card in the list (experience_package_card.dart) and its
// page (experience_package_detail_page.dart). `pkg` is what the server's
// preview endpoint returns: the same data the app gets, so every label
// (price with commission and dollars, duration, place) is the app's own.

// experience_category.dart: value → label, Material icon, accent.
const CATEGORIES = {
  boat: ['Boat ride', 'sailing', '#0284C7', ['#38BDF8', '#0369A1']],
  water_sports: ['Water sports', 'surfing', '#0891B2', ['#22D3EE', '#0E7490']],
  guided_tour: ['Guided tour', 'explore', '#D97706', ['#FBBF24', '#B45309']],
  wildlife: ['Wildlife', 'pets', '#16A34A', ['#4ADE80', '#15803D']],
  cultural: ['Cultural', 'temple_buddhist', '#9333EA', ['#C084FC', '#7E22CE']],
  adventure: ['Adventure', 'hiking', '#EA580C', ['#FB923C', '#C2410C']],
  food: ['Food', 'restaurant', '#E11D48', ['#FB7185', '#BE123C']],
};
const GENERIC = ['Experience', 'grid_view', '#007A7C', ['#00A3A6', '#005E60']];
const categoryOf = (value) => CATEGORIES[value] || GENERIC;

/** Experience.formattedDuration, word for word. */
function formattedDuration(p) {
  const mins = p.duration_minutes;
  if (mins > 0) {
    const h = Math.floor(mins / 60);
    const m = mins % 60;
    if (h > 0 && m > 0) return `${h} hr ${m} mins duration`;
    if (h > 0) return h === 1 ? '1 Hour Duration' : `${h} Hours Duration`;
    return `${m} Mins Duration`;
  }
  const label = (p.duration_label || '').trim();
  if (!label) return '';
  const clean = label.toLowerCase();
  if (clean === '1h') return '1 Hour Duration';
  if (clean.endsWith('h')) return `${clean.slice(0, -1)} Hours Duration`;
  if (clean.endsWith('m')) return `${clean.slice(0, -1)} Mins Duration`;
  return `${label} Duration`;
}

/** The card's price corner: "LKR 45,395" big, "($137) per group (max 4)" small. */
function Price({ pkg }) {
  const label = (pkg.display_label || pkg.price_label || '').trim();
  if (!label) return null;
  const parts = label.split(' / ');
  const dollars = parts[0].match(/^(.*) \((\$[^)]*)\)$/);
  const amount = dollars ? dollars[1] : parts[0];
  const rawUnit = parts.length > 1 ? parts.slice(1).join(' / ').trim() : null;
  const unit = rawUnit ? (rawUnit.toLowerCase().startsWith('per ') ? rawUnit : `per ${rawUnit}`) : null;
  const small = [dollars && `(${dollars[2]})`, unit].filter(Boolean).join(' ');
  const onRequest = pkg.price_amount == null || pkg.price_basis === 'on_request';
  return (
    <span className="xpp-price">
      <span className={`xpp-price-main ${onRequest ? 'on-request' : ''}`}>{amount}</span>
      {small && <span className="xpp-price-small">{small}</span>}
      {pkg.price_options.length > 1 && <span className="xpp-price-more">{pkg.price_options.length} price options</span>}
    </span>
  );
}

function Stars({ value, size }) {
  return (
    <span className="xpp-stars">
      {[1, 2, 3, 4, 5].map((i) => (
        <MIcon key={i} size={size} color="#F59E0B" name={value >= i ? 'star' : value >= i - 0.5 ? 'star_half' : 'star_border'} />
      ))}
    </span>
  );
}

function Card({ pkg }) {
  const [label, icon, accent, tint] = categoryOf(pkg.category);
  const duration = formattedDuration(pkg).replace(/\s+duration/i, '').trim();
  return (
    <div className="xpp-card">
      <div className="xpp-thumb" style={{ background: `linear-gradient(135deg, ${tint[0]}, ${tint[1]})` }}>
        {pkg.cover_photo_url
          ? <img src={mediaUrl(pkg.cover_photo_url)} alt="" />
          : <MIcon name={icon} size={34} color="rgba(255,255,255,0.9)" />}
        {pkg.photo_count > 1 && (
          <span className="xpp-thumb-count"><MIcon name="photo_library" size={9.5} /> {pkg.photo_count}</span>
        )}
      </div>
      <div className="xpp-card-body">
        <div className="xpp-card-top">
          <span className="xpp-cat" style={{ color: accent, background: `${accent}1f` }}>
            <MIcon name={icon} size={10} /> {label}
          </span>
          {(pkg.region_label || '').trim() && (
            <span className="xpp-region"><MIcon name="location_on" size={10.5} /> <span>{pkg.region_label.trim()}</span></span>
          )}
        </div>
        <div className="xpp-card-title">{pkg.title || 'Package title'}</div>
        <div className="xpp-vendor">
          <MIcon name="storefront" size={12} /> <span>{pkg.vendor_name}</span>
          {pkg.rating_avg != null && pkg.rating_count > 0 && (
            <span className="xpp-card-rating"><MIcon name="star" size={11} color="#F59E0B" /> {pkg.rating_avg.toFixed(1)} ({pkg.rating_count})</span>
          )}
        </div>
        <div className="xpp-card-foot">
          {duration && <span className="xpp-duration"><MIcon name="schedule" size={10.5} /> {duration}</span>}
          <Price pkg={pkg} />
        </div>
      </div>
    </div>
  );
}

function ListScreen({ pkg }) {
  return (
    <div className="xpp-list">
      <StatusBar />
      <div className="xpp-list-head">
        <MIcon name="arrow_back" size={22} />
        <span>Experiences</span>
      </div>
      <div className="xpp-list-hint">How the package shows in the app’s Experiences list.</div>
      <Card pkg={pkg} />
      <div className="xpp-card xpp-card-ghost" />
      <div className="xpp-card xpp-card-ghost" />
    </div>
  );
}

function Chip({ icon, children, highlight }) {
  return <span className={`xpp-chip ${highlight ? 'on' : ''}`}><MIcon name={icon} size={14} /> {children}</span>;
}

function PackagePage({ pkg }) {
  const photos = pkg.photo_urls || [];
  const [index, setIndex] = useState(0);
  const at = Math.min(index, Math.max(photos.length - 1, 0));
  const tint = categoryOf(pkg.category)[3];
  const duration = formattedDuration(pkg);
  const vendor = pkg.vendor || {};
  const aboutVendor = (vendor.description || '').trim() || (vendor.address || '').trim() || vendor.website;
  return (
    <div className="xpp-page">
      <div className="xpp-hero" style={{ background: `linear-gradient(135deg, ${tint[0]}, ${tint[1]})` }}>
        {photos[at]
          ? <img src={mediaUrl(photos[at])} alt="" />
          : <MIcon name="kayaking" size={64} color="rgba(255,255,255,0.85)" />}
        <div className="xpp-hero-top"><StatusBar light /></div>
        <span className="xpp-hero-btn left"><MIcon name="arrow_back_ios_new" size={18} /></span>
        <span className="xpp-hero-btn right"><MIcon name="ios_share" size={18} /></span>
        {pkg.video_urls?.length > 0 && <span className="xpp-hero-video"><MIcon name="play_circle" size={14} /> {pkg.video_urls.length} video{pkg.video_urls.length === 1 ? '' : 's'} first</span>}
        {photos.length > 1 && (
          <span className="xpp-hero-dots">
            {photos.map((p, i) => (
              <button key={i} type="button" className={i === at ? 'on' : ''} onClick={() => setIndex(i)} aria-label={`Photo ${i + 1}`} />
            ))}
          </span>
        )}
      </div>
      <div className="xpp-body">
        <div className="xpp-title">{pkg.title || 'Package title'}</div>
        <div className="xpp-by">{pkg.vendor_name}</div>
        {pkg.rating_avg != null && pkg.rating_count > 0 && (
          <div className="xpp-rating">
            <Stars value={pkg.rating_avg} size={17} />
            <strong>{pkg.rating_avg.toFixed(1)} ({pkg.rating_count} {pkg.rating_count === 1 ? 'review' : 'reviews'})</strong>
          </div>
        )}
        {(pkg.region_label || '').trim() && (
          <div className="xpp-place"><MIcon name="location_on" size={16} color="#007A7C" /> {pkg.region_label.trim()}</div>
        )}
        <div className="xpp-chips">
          {pkg.price_label && pkg.price_options.length < 2 && <Chip icon="sell" highlight>{pkg.display_label || pkg.price_label}</Chip>}
          {duration && <Chip icon="schedule">{duration}</Chip>}
          {pkg.max_participants != null && <Chip icon="group">Up to {pkg.max_participants}</Chip>}
        </div>
        {pkg.price_options.length > 1 && (
          <>
            <div className="xpp-h">Prices</div>
            {pkg.price_options.map((o, i) => (
              <div key={i} className="xpp-line"><MIcon name="sell" size={16} color="#007A7C" /> <span>{o.display_label || o.label}</span></div>
            ))}
            <div className="xpp-note">Choose one when you ask to book.</div>
          </>
        )}
        {(pkg.summary || '').trim() && <div className="xpp-summary">{pkg.summary}</div>}
        {(pkg.description_md || pkg.description || '').trim() && (
          <div className="xpp-desc"><AppMarkdown text={pkg.description_md || pkg.description} /></div>
        )}
        {pkg.inclusions?.length > 0 && (
          <>
            <div className="xpp-h" style={{ marginTop: 24 }}>What’s included</div>
            {pkg.inclusions.map((item, i) => (
              <div key={i} className="xpp-line"><MIcon name="check_circle" size={16} color="#007A7C" /> <span>{item}</span></div>
            ))}
          </>
        )}
        {pkg.languages?.length > 0 && (
          <>
            <div className="xpp-h">Languages</div>
            <div className="xpp-text">{pkg.languages.join(', ')}</div>
          </>
        )}
        {(pkg.meeting_point_address || '').trim() && (
          <>
            <div className="xpp-h">Meeting point</div>
            <div className="xpp-link"><MIcon name="place" size={15} /> <span>{pkg.meeting_point_address}</span></div>
          </>
        )}
        <div className="xpp-h" style={{ marginTop: 24 }}>Reviews</div>
        <div className="xpp-text">
          {pkg.rating_count > 0
            ? `${pkg.rating_count} ${pkg.rating_count === 1 ? 'review' : 'reviews'} from travellers.`
            : 'No reviews yet. Be the first to share how it went.'}
        </div>
        {aboutVendor && (
          <>
            <div className="xpp-h" style={{ marginTop: 24 }}>About {vendor.name}</div>
            {(vendor.description || '').trim() && <div className="xpp-text xpp-about">{vendor.description}</div>}
            {(vendor.address || '').trim() && <div className="xpp-link"><MIcon name="place" size={15} /> <span>{vendor.address}</span></div>}
            {vendor.website && <div className="xpp-link"><MIcon name="link" size={15} /> <span>Visit website</span></div>}
          </>
        )}
        <div className="xpp-h" style={{ marginTop: 24 }}>Good to know</div>
        <div className="xpp-text">Booking terms, cancellations and what to bring. <span className="xpp-terms">Read full terms</span></div>
      </div>
      <div className="xpp-bar">
        <span className="xpp-bar-icon"><MIcon name="call" size={22} /></span>
        <span className="xpp-bar-icon"><MIcon name="chat" size={22} color="#25D366" /></span>
        <span className="xpp-book">Request booking</span>
      </div>
    </div>
  );
}

/**
 * A phone showing the package as travellers will see it. `pkg` is the
 * server's preview of the form (null until the first one arrives);
 * `waiting` says the form changed since; `problem` why it could not update.
 */
export default function ExperiencePreview({ pkg, waiting, problem }) {
  const [screen, setScreen] = useState('page');
  let note = 'As in the app. Prices, duration and place come from the server, as the app gets them.';
  if (problem) note = `Preview paused: ${problem}`;
  else if (waiting) note = 'Updating…';
  return (
    <PhoneFrame tabs={[['list', 'In the list'], ['page', 'Package page']]} tab={screen} onTab={setScreen} note={note}>
      {!pkg ? (
        <div className="xpp-loading"><StatusBar /><span>Loading the preview…</span></div>
      ) : screen === 'list' ? <ListScreen pkg={pkg} /> : <PackagePage pkg={pkg} />}
    </PhoneFrame>
  );
}
