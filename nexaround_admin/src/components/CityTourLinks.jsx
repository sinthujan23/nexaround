import { useEffect, useMemo, useState } from 'react';
import { apiGet, mediaUrl } from '../api';
import { newId, partnerLogo } from '../cityTours';
import { Modal, SearchBar } from './Kit';
import { CrossIcon, LinkIcon, PlusIcon, TicketIcon } from './Icons';

// Partner links are never typed. Picking a partner is enough: the server makes
// the page from the guide (city_tours.partner_page) when it is saved, and only
// WeGoTrip needs a choice, of a ticket from the city's own catalogue.

// What each partner can open from a guide in a given city and stop, from the
// server. Kept for the page's life: WeGoTrip's catalogue is a hundred-odd rows.
const optionsCache = new Map();

function loadOptions(where) {
  const key = [where.city, where.country, where.place].map((v) => (v || '').trim().toLowerCase()).join('|');
  if (!optionsCache.has(key)) {
    const params = new URLSearchParams({ city: where.city || '', country: where.country || '', place: where.place || '' });
    optionsCache.set(key, apiGet(`/admin/city-tours/partner-options?${params}`).catch((err) => {
      optionsCache.delete(key);
      throw err;
    }));
  }
  return optionsCache.get(key);
}

function usePartnerOptions(where, active) {
  const key = [where.city, where.country, where.place].join('|');
  const [state, setState] = useState({ key: null, data: null, error: '' });
  useEffect(() => {
    if (!active) return undefined;
    let live = true;
    loadOptions(where)
      .then((data) => { if (live) setState({ key, data, error: '' }); })
      .catch((err) => { if (live) setState({ key, data: null, error: err.message || 'Could not load the partners.' }); });
    return () => { live = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, active]);
  return state.key === key ? state : { data: null, error: '' };
}

/** What Klook is searched for: as city_tours.klook_query on the server. */
function klookQuery(words, where) {
  const w = (words || (where.isStop ? where.stopName : '') || '').trim();
  const city = (where.city || '').trim();
  if (city && w.toLowerCase().includes(city.toLowerCase())) return w;
  return [w, city].filter(Boolean).join(' ');
}

const placeName = (stop, city) => [stop, city].filter(Boolean).join(', ');

/** A new link to this partner, with its button text written for the stop. */
function newPartnerLink(partner, where, options) {
  const base = { id: newId(), kind: 'affiliate', partner };
  const city = where.city || 'the city';
  if (partner === 'klook') {
    return {
      ...base, words: '',
      label: (where.isStop && where.stopName ? `${where.stopName}: tours and tickets` : `Things to do in ${city}`).slice(0, 80),
    };
  }
  if (partner === 'wegotrip') {
    const products = options?.wegotrip?.products || [];
    const pick = products.find((p) => p.id === options?.wegotrip?.best) || products[0];
    return { ...base, url: pick?.url || '', product_title: pick?.title || '', label: (pick?.title || '').slice(0, 80) };
  }
  if (partner === 'gocity') return { ...base, label: `${city} sightseeing pass`.slice(0, 80) };
  if (partner === 'airalo') return { ...base, label: `${where.country || 'Local'} eSIM for mobile data`.slice(0, 80) };
  return {
    ...base,
    label: (where.isStop ? `Book a car to ${where.stopName || 'here'}` : 'Book a car to the next stop').slice(0, 80),
  };
}

/** One line saying what the button opens, so nobody has to read an address. */
function Opens({ link, where, options }) {
  const city = where.city || 'the city';
  let text;
  let warn = false;
  if (link.partner === 'klook') {
    const query = klookQuery(link.words, where);
    text = query ? `Klook's results for “${query}”` : 'Add the words to search Klook for.';
    warn = !query;
  } else if (link.partner === 'wegotrip') {
    text = link.url ? `This ticket's page on WeGoTrip` : 'Pick the ticket or tour.';
    warn = !link.url;
  } else if (link.partner === 'gocity') {
    warn = options?.gocity?.available === false;
    text = warn ? `${options.gocity.reason} Remove this link.` : `Go City's ${city} pass page`;
  } else if (link.partner === 'airalo') {
    warn = !where.country;
    text = warn ? "Add the guide's country first." : `Airalo's ${where.country} eSIM page`;
  } else if (where.isStop) {
    text = `GetTransfer's booking form, drop-off at ${placeName(where.stopName, where.city) || 'this stop'}. The traveller says where from.`;
  } else {
    text = `GetTransfer from ${placeName(where.prevStop, where.city) || 'the stop before'} to ${placeName(where.nextStop, where.city) || 'the next stop'}`;
  }
  return <div className={`ctl-opens ${warn ? 'warn' : ''}`}>Opens: {text}</div>;
}

/**
 * Choose what a link opens: an Experience listed in the app, or a partner's
 * site. Only what travellers can see anyway is listed.
 */
function PartnerPicker({ partners, where, onPick, onClose }) {
  const [tab, setTab] = useState('experiences');
  const [query, setQuery] = useState('');
  const options = usePartnerOptions(where, tab === 'sites');
  const experiences = partners?.experiences;
  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    return (experiences || []).filter((p) => !q
      || [p.title, p.vendor_name, p.place].some((v) => (v || '').toLowerCase().includes(q)));
  }, [experiences, query]);

  return (
    <Modal title="Add a partner link" onClose={onClose} maxWidth="720px">
      <div className="seg" style={{ marginBottom: 14 }}>
        <button type="button" className={`seg-btn ${tab === 'experiences' ? 'active' : ''}`} onClick={() => setTab('experiences')}>
          Experiences <span className="seg-count">{experiences?.length || 0}</span>
        </button>
        <button type="button" className={`seg-btn ${tab === 'sites' ? 'active' : ''}`} onClick={() => setTab('sites')}>
          Partner websites <span className="seg-count">{partners?.affiliates?.length || 0}</span>
        </button>
      </div>

      {tab === 'experiences' ? (
        <>
          <div className="xp-section-hint">
            Tours and trips from our vendors. The button opens the experience in the app, where travellers send their request.
          </div>
          <SearchBar
            value={query} onChange={setQuery} placeholder="Search by name, vendor or place"
            style={{ width: '100%', marginBottom: 12 }}
          />
          <div className="ctl-pick-list">
            {shown.length === 0 && <div className="xp-section-hint">No experience matches.</div>}
            {shown.map((p) => (
              <button
                key={p.id} type="button" className="ctl-pick-row"
                onClick={() => onPick({ id: newId(), kind: 'experience', package_id: p.id, label: '' })}
              >
                <span className="ctl-thumb">
                  {p.photo_url ? <img src={mediaUrl(p.photo_url)} alt="" /> : <TicketIcon size={18} />}
                </span>
                <span className="ctl-pick-main">
                  <strong>{p.title}</strong>
                  <span>{[p.vendor_name, p.place].filter(Boolean).join(' · ')}</span>
                </span>
                <span className="ctl-pick-price">{p.price_label}</span>
              </button>
            ))}
          </div>
        </>
      ) : (
        <>
          <div className="xp-section-hint">
            Pick a partner: the link is made for you from this stop and the guide’s city, with our partner code, so bookings are credited to us.
          </div>
          {options.error && <div className="cte-error" style={{ marginBottom: 10 }}>{options.error}</div>}
          <div className="ctl-site-grid">
            {(partners?.affiliates || []).map((a) => {
              const state = options.data?.[a.key];
              const disabled = !options.data || !state?.available;
              return (
                <button
                  key={a.key} type="button" className="ctl-site" disabled={disabled}
                  onClick={() => onPick(newPartnerLink(a.key, where, options.data))}
                >
                  <img src={partnerLogo(a.key)} alt="" />
                  <span>
                    <strong>{a.name}</strong>
                    <span>{a.what}</span>
                    {options.data && !state?.available
                      ? <span className="ctl-site-off">{state?.reason || 'Not available here.'}</span>
                      : <span className="ctl-site-domain">{options.data ? a.domain : 'Checking…'}</span>}
                  </span>
                </button>
              );
            })}
          </div>
        </>
      )}
    </Modal>
  );
}

/**
 * The partner buttons on one step of a guide. `where` is the step's place in
 * the guide: { city, country, isStop, stopName, place, prevStop, nextStop }.
 * `taps` (admins only): link id → taps.
 */
export default function CityTourLinks({ links, onChange, partners, taps, where }) {
  const [picking, setPicking] = useState(false);
  // An index while changing which Experience a link opens.
  const [replacing, setReplacing] = useState(null);
  // The city's options; the stop's name only ranks WeGoTrip's list in the
  // picker, so typing it does not fetch the catalogue again.
  const options = usePartnerOptions({ ...where, place: '' }, links.some((l) => l.kind !== 'experience'));

  const update = (i, patch) => onChange(links.map((l, j) => (j === i ? { ...l, ...patch } : l)));
  const remove = (i) => onChange(links.filter((_, j) => j !== i));

  const pick = (link) => {
    if (replacing !== null) {
      update(replacing, { ...link, id: links[replacing].id, label: links[replacing].label });
    } else {
      onChange([...links, link]);
    }
    setPicking(false);
    setReplacing(null);
  };

  // Another ticket; the button text follows unless it was written by hand.
  const pickProduct = (i, url) => {
    const link = links[i];
    const product = (options.data?.wegotrip?.products || []).find((p) => p.url === url);
    if (!product) return;
    const ownText = link.label && link.label !== (link.product_title || '').slice(0, 80);
    update(i, { url: product.url, product_title: product.title, ...(ownText ? {} : { label: product.title.slice(0, 80) }) });
  };

  return (
    <div className="ctl">
      {links.map((link, i) => {
        const affiliate = (partners?.affiliates || []).find((a) => a.key === link.partner);
        const pkg = (partners?.experiences || []).find((p) => p.id === link.package_id);
        const isExperience = link.kind === 'experience';
        const count = taps?.[link.id];
        const products = options.data?.wegotrip?.products || [];
        return (
          <div key={link.id} className="ctl-row">
            <div className="ctl-row-head">
              <span className="ctl-thumb">
                {isExperience
                  ? (pkg?.photo_url ? <img src={mediaUrl(pkg.photo_url)} alt="" /> : <TicketIcon size={16} />)
                  : <img src={partnerLogo(link.partner)} alt="" />}
              </span>
              <div className="ctl-row-title">
                <strong>{isExperience ? (pkg?.title || 'Experience no longer listed') : affiliate?.name || link.partner}</strong>
                <span>{isExperience ? `Experience${pkg ? ` · ${pkg.vendor_name}` : ''} · opens in the app` : `${affiliate?.what || ''} · opens their site`}</span>
              </div>
              {taps && <span className="ctl-taps" title="Taps by travellers, all time">{count || 0} taps</span>}
              {isExperience && (
                <button type="button" className="btn btn-ghost btn-sm" onClick={() => { setReplacing(i); setPicking(true); }}>
                  Change
                </button>
              )}
              <button type="button" className="icon-btn" title="Remove this link" onClick={() => remove(i)}>
                <CrossIcon size={16} />
              </button>
            </div>
            <div className={link.partner === 'klook' || link.partner === 'wegotrip' ? 'form-grid-2' : ''}>
              <div className="form-group">
                <label className="form-label">Button text</label>
                <input
                  className="form-input" maxLength={80} value={link.label}
                  placeholder={isExperience ? (pkg?.title || 'The experience’s name') : `Book on ${affiliate?.name || 'the partner’s site'}`}
                  onChange={(e) => update(i, { label: e.target.value })}
                />
              </div>
              {link.partner === 'klook' && (
                <div className="form-group">
                  <label className="form-label">Search Klook for</label>
                  <input
                    className="form-input" maxLength={80} value={link.words || ''}
                    placeholder={where.isStop && where.stopName ? where.stopName : 'e.g. Seine cruise'}
                    onChange={(e) => update(i, { words: e.target.value })}
                  />
                </div>
              )}
              {link.partner === 'wegotrip' && (
                <div className="form-group">
                  <label className="form-label">Ticket or tour</label>
                  <select className="form-input" value={link.url || ''} onChange={(e) => pickProduct(i, e.target.value)}>
                    {!link.url && <option value="">Pick one…</option>}
                    {link.url && !products.some((p) => p.url === link.url) && (
                      <option value={link.url}>{link.product_title || 'The ticket picked before'}</option>
                    )}
                    {products.map((p) => (
                      <option key={p.id} value={p.url}>{p.title} · {p.price_label}</option>
                    ))}
                  </select>
                </div>
              )}
            </div>
            {!isExperience && <Opens link={link} where={where} options={options.data} />}
          </div>
        );
      })}
      {links.length < 6 && (
        <button type="button" className="btn btn-ghost btn-sm" onClick={() => { setReplacing(null); setPicking(true); }}>
          {links.length ? <PlusIcon size={14} /> : <LinkIcon size={14} />} Add partner link
        </button>
      )}
      {picking && (
        <PartnerPicker
          partners={partners}
          where={where}
          onPick={pick}
          onClose={() => { setPicking(false); setReplacing(null); }}
        />
      )}
    </div>
  );
}
