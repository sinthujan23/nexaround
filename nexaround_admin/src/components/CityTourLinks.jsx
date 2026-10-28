import { useMemo, useState } from 'react';
import { mediaUrl } from '../api';
import { newId, partnerLogo } from '../cityTours';
import { Modal, SearchBar } from './Kit';
import { CrossIcon, LinkIcon, PlusIcon, TicketIcon } from './Icons';

/**
 * Choose what a link opens: an Experience listed in the app, or one of the
 * affiliate partners' websites. Only what travellers can see anyway is listed.
 */
function PartnerPicker({ partners, onPick, onClose }) {
  const [tab, setTab] = useState('experiences');
  const [query, setQuery] = useState('');
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
                onClick={() => onPick({ kind: 'experience', package_id: p.id })}
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
            Pick the partner, then paste the page on their site you want travellers to open. Our partner code is added when they tap, so bookings are credited to us.
          </div>
          <div className="ctl-site-grid">
            {(partners?.affiliates || []).map((a) => (
              <button
                key={a.key} type="button" className="ctl-site"
                onClick={() => onPick({ kind: 'affiliate', partner: a.key, url: '' })}
              >
                <img src={partnerLogo(a.key)} alt="" />
                <span>
                  <strong>{a.name}</strong>
                  <span>{a.what}</span>
                  <span className="ctl-site-domain">{a.domain}</span>
                </span>
              </button>
            ))}
          </div>
        </>
      )}
    </Modal>
  );
}

/** The partner buttons on one step of a guide. `taps` (admins only): link id → taps. */
export default function CityTourLinks({ links, onChange, partners, taps }) {
  const [picking, setPicking] = useState(false);
  // An index while changing which Experience a link opens.
  const [replacing, setReplacing] = useState(null);

  const update = (i, patch) => onChange(links.map((l, j) => (j === i ? { ...l, ...patch } : l)));
  const remove = (i) => onChange(links.filter((_, j) => j !== i));

  const pick = (choice) => {
    if (replacing !== null) {
      update(replacing, choice);
    } else {
      onChange([...links, { id: newId(), label: '', ...choice }]);
    }
    setPicking(false);
    setReplacing(null);
  };

  return (
    <div className="ctl">
      {links.map((link, i) => {
        const affiliate = (partners?.affiliates || []).find((a) => a.key === link.partner);
        const pkg = (partners?.experiences || []).find((p) => p.id === link.package_id);
        const isExperience = link.kind === 'experience';
        const count = taps?.[link.id];
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
                <span>{isExperience ? `Experience${pkg ? ` · ${pkg.vendor_name}` : ''} · opens in the app` : `${affiliate?.domain || ''} · opens their site`}</span>
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
            <div className={isExperience ? '' : 'form-grid-2'}>
              <div className="form-group" style={{ marginBottom: isExperience ? 0 : undefined }}>
                <label className="form-label">Button text</label>
                <input
                  className="form-input" maxLength={80} value={link.label}
                  placeholder={isExperience ? (pkg?.title || 'The experience’s name') : `Book on ${affiliate?.name || 'the partner’s site'}`}
                  onChange={(e) => update(i, { label: e.target.value })}
                />
              </div>
              {!isExperience && (
                <div className="form-group">
                  <label className="form-label">Page on {affiliate?.domain || 'their site'} *</label>
                  <input
                    className="form-input" maxLength={1000} value={link.url} type="url"
                    placeholder={affiliate?.example || 'https://'}
                    onChange={(e) => update(i, { url: e.target.value.trim() })}
                  />
                </div>
              )}
            </div>
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
          onPick={pick}
          onClose={() => { setPicking(false); setReplacing(null); }}
        />
      )}
    </div>
  );
}
