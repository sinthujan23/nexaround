import { useCallback, useEffect, useRef, useState } from 'react';
import { apiDownload, apiGet, apiPost } from '../api';
import {
  BarChartIcon, BugIcon, CrossIcon, HeartIcon, InboxIcon, LightbulbIcon, MegaphoneIcon,
  MessageCircleIcon, RefreshIcon, SearchIcon, SendIcon, SlidersIcon, ThumbsDownIcon, ThumbsUpIcon,
  TrendingUpIcon,
} from '../components/Icons';
import { Toast } from '../components/Kit';
import { useToast } from '../hooks';
import { notifyFeedbackChanged } from '../feedbackCount';
import { SurveyResults, SurveySettings } from './FeedbackSurvey';
import {
  FEATURE_LABELS, formatDate, formatDateTime, formatWhen,
} from '../feedbackShared';

// What explorers tell us (client request, 2026-11-26): the "Tell us what you
// want" form, the one-tap "How was it?" after an Odyssey plan / City Guide trip
// / Walking Challenge, and the quarterly survey. Replies reach the explorer as
// a bell line, a push and an email from support@.

const TYPES = {
  suggestion: { label: 'Suggestion', Icon: LightbulbIcon, tone: 'amber' },
  improvement: { label: 'Improvement', Icon: TrendingUpIcon, tone: 'blue' },
  problem: { label: 'Problem', Icon: BugIcon, tone: 'red' },
  love: { label: 'Love it', Icon: HeartIcon, tone: 'pink' },
  other: { label: 'Other', Icon: MessageCircleIcon, tone: 'slate' },
  good: { label: 'Good', Icon: ThumbsUpIcon, tone: 'green' },
  bad: { label: 'Not great', Icon: ThumbsDownIcon, tone: 'red' },
};

const FILTERS = [
  { key: 'all', label: 'All', Icon: InboxIcon },
  { key: 'new', label: 'New', Icon: MegaphoneIcon, countKey: 'new' },
  { key: 'suggestion', label: 'Suggestions', Icon: LightbulbIcon },
  { key: 'improvement', label: 'Improvements', Icon: TrendingUpIcon },
  { key: 'problem', label: 'Problems', Icon: BugIcon },
  { key: 'love', label: 'Love it', Icon: HeartIcon },
  { key: 'other', label: 'Other', Icon: MessageCircleIcon },
  { key: 'quick', label: 'Quick ratings', Icon: ThumbsDownIcon, countKey: 'new_quick' },
];

const STATUSES = [
  ['new', 'New'], ['seen', 'Seen'], ['planned', 'Planned'], ['done', 'Done'], ['replied', 'Replied'], ['closed', 'Closed'],
];

const REASONS = {
  wrong_places: 'Wrong places', too_rushed: 'Too rushed', prices_off: 'Prices were off',
  route_confusing: 'Route confusing', places_closed: 'Places were closed', too_long: 'Too long',
  too_far: 'Too far to walk', clues_hard: 'Clues too hard', map_problem: 'Map problem', other: 'Other',
};

const SCREENS = {
  home: 'Home card', tell_us: 'Tell us button', profile: 'Profile', odyssey: 'Odyssey plan', city_guides: 'City Guide',
  walking_challenge: 'Walking Challenge', my_feedback: 'My feedback',
};

const COLORS = ['#0e7c86', '#7c3aed', '#db2777', '#ea580c', '#2563eb', '#059669', '#ca8a04', '#475569', '#dc2626'];

const flag = (cc) => (cc && /^[A-Z]{2}$/.test(cc)
  ? String.fromCodePoint(...[...cc].map((c) => 0x1f1a5 + c.charCodeAt(0))) : '');
const countryName = (cc) => {
  try { return cc ? new Intl.DisplayNames(['en'], { type: 'region' }).of(cc) : ''; } catch { return cc; }
};

function Avatar({ name, email, size = 36 }) {
  const label = name || (email || '?').split('@')[0];
  const words = label.replace(/[^\p{L}\p{N}\s]/gu, ' ').trim().split(/\s+/).filter(Boolean);
  const initials = ((words[0]?.[0] || '?') + (words.length > 1 ? words[words.length - 1][0] : '')).toUpperCase();
  let hash = 0;
  const key = email || label;
  for (let i = 0; i < key.length; i += 1) hash = Math.imul(hash ^ key.charCodeAt(i), 2654435761) >>> 0;
  return (
    <span className="mbx-avatar" aria-hidden="true"
      style={{ width: size, height: size, fontSize: Math.round(size * 0.38), background: COLORS[hash % COLORS.length] }}>
      {initials}
    </span>
  );
}

function TypeChip({ type }) {
  const t = TYPES[type] || TYPES.other;
  return <span className={`fb-chip tone-${t.tone}`}><t.Icon size={12} /> {t.label}</span>;
}

function StatusChip({ status }) {
  const label = (STATUSES.find(([k]) => k === status) || [status, status])[1];
  return <span className={`fb-status st-${status}`}>{label}</span>;
}

/** A private screenshot: fetched with the panel's token, shown from a blob. */
function Shot({ feedbackId, index, onOpen }) {
  const [url, setUrl] = useState(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let alive = true;
    let made = null;
    apiDownload(`/admin/feedback/${feedbackId}/screenshots/${index}`)
      .then((blob) => {
        made = URL.createObjectURL(blob);
        if (alive) setUrl(made); else URL.revokeObjectURL(made);
      })
      .catch(() => { if (alive) setFailed(true); });
    return () => { alive = false; if (made) URL.revokeObjectURL(made); };
  }, [feedbackId, index]);
  if (failed) return <div className="fb-shot fb-shot-missing">Picture not available</div>;
  if (!url) return <div className="fb-shot fb-shot-loading" />;
  return (
    <button type="button" className="fb-shot" onClick={() => onOpen(url)} title="Open full size">
      <img src={url} alt={`Screenshot ${index + 1}`} />
    </button>
  );
}

function Messages({ counts, onChanged, notify }) {
  const [filter, setFilter] = useState('all');
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const [list, setList] = useState(null);
  const [error, setError] = useState(null);
  const [loadingMore, setLoadingMore] = useState(false);
  const [selectedId, setSelectedId] = useState(null);
  const [item, setItem] = useState(null);
  const [itemError, setItemError] = useState(null);
  const [reply, setReply] = useState('');
  const [sending, setSending] = useState(false);
  const [lightbox, setLightbox] = useState(null);
  const [reloads, setReloads] = useState(0);
  const run = useRef(0);
  const openRun = useRef(0);

  useEffect(() => {
    const t = setTimeout(() => {
      const next = search.trim();
      setQuery((prev) => { if (prev !== next) setList(null); return next; });
    }, 400);
    return () => clearTimeout(t);
  }, [search]);

  const url = useCallback((page) => {
    const p = new URLSearchParams({ filter, page: String(page) });
    if (query) p.set('q', query);
    return `/admin/feedback?${p}`;
  }, [filter, query]);

  useEffect(() => {
    const r = ++run.current;
    apiGet(url(1))
      .then((res) => { if (r === run.current) { setError(null); setList(res); } })
      .catch((err) => { if (r === run.current) setError(err.message || 'Could not load feedback.'); });
  }, [url, reloads]);

  const loadMore = async () => {
    const r = ++run.current;
    setLoadingMore(true);
    try {
      const res = await apiGet(url((list?.page || 1) + 1));
      if (r === run.current) setList((prev) => ({ ...res, items: [...(prev?.items || []), ...res.items] }));
    } catch (err) {
      notify(err.message || 'Could not load more.', 'error');
    } finally {
      setLoadingMore(false);
    }
  };

  const patchRow = (next) => setList((prev) => prev && {
    ...prev, items: prev.items.map((x) => (x.id === next.id ? { ...x, ...next } : x)),
  });

  const open = async (id) => {
    const r = ++openRun.current;
    setSelectedId(id);
    setItem(null);
    setItemError(null);
    setReply('');
    try {
      const res = await apiGet(`/admin/feedback/${id}`);
      if (r !== openRun.current) return;
      setItem(res);
      patchRow(res);
      onChanged();
    } catch (err) {
      if (r === openRun.current) setItemError(err.message || 'Could not open this.');
    }
  };

  const close = () => { openRun.current += 1; setSelectedId(null); setItem(null); setItemError(null); };

  const switchFilter = (key) => {
    if (key === filter) return;
    setFilter(key);
    setList(null);
    close();
  };

  const refresh = () => { setList(null); setReloads((n) => n + 1); onChanged(); };

  const setStatus = async (status) => {
    try {
      await apiPost(`/admin/feedback/${item.id}/status`, { status });
      const next = { ...item, status };
      setItem(next);
      patchRow(next);
      onChanged();
      notify(`Marked as ${(STATUSES.find(([k]) => k === status) || [status, status])[1]}`);
    } catch (err) {
      notify(err.message || 'Could not change the status.', 'error');
    }
  };

  const sendReply = async (e) => {
    e.preventDefault();
    if (reply.trim().length < 2) { notify('Write a reply first.', 'error'); return; }
    setSending(true);
    try {
      const res = await apiPost(`/admin/feedback/${item.id}/reply`, { text: reply.trim() });
      setItem(res.item);
      patchRow(res.item);
      setReply('');
      onChanged();
      const parts = [res.sent.bell && 'in the app', res.sent.push && 'as a push', res.sent.email && 'by email'].filter(Boolean);
      notify(`Reply sent ${parts.join(', ')}.`);
    } catch (err) {
      notify(err.message || 'The reply could not be sent.', 'error');
    } finally {
      setSending(false);
    }
  };

  const items = list?.items || [];
  const explorer = item?.explorer;

  return (
    <div className={`mbx ${selectedId ? 'has-selection' : ''}`}>
      <nav className="mbx-folders" aria-label="Filters">
        <div className="mbx-folder-list">
          {FILTERS.map(({ key, label, Icon, countKey }) => {
            const n = countKey ? counts?.[countKey] : null;
            return (
              <button type="button" key={key} className={`mbx-folder ${filter === key ? 'active' : ''}`} onClick={() => switchFilter(key)}>
                <Icon size={17} />
                <span>{label}</span>
                {n ? <em className="pill">{n.toLocaleString()}</em> : null}
              </button>
            );
          })}
        </div>
        <div className="mbx-folder-note">
          <b>Quick ratings</b> lists only the &ldquo;Not great&rdquo; taps. The &ldquo;Good&rdquo; ones are counted on the Survey results tab.
        </div>
      </nav>

      <section className="mbx-list" aria-label="Feedback">
        <div className="mbx-list-head">
          <div className="mbx-search">
            <SearchIcon size={16} />
            <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search text or explorer" aria-label="Search feedback" />
            {search && (
              <button type="button" className="mbx-search-clear" onClick={() => setSearch('')} title="Clear search"><CrossIcon size={14} /></button>
            )}
          </div>
          <div className="mbx-filters">
            <span className="mbx-list-count" style={{ marginTop: 0 }}>
              {list ? `${list.total.toLocaleString()} ${list.total === 1 ? 'item' : 'items'}` : 'Loading…'}
            </span>
            <button type="button" className="mbx-icon-btn mbx-refresh" onClick={refresh} title="Check for new feedback"><RefreshIcon size={15} /></button>
          </div>
        </div>
        <div className="mbx-list-body">
          {error && <div className="login-error" style={{ margin: 12 }}>{error}</div>}
          {!list && !error && <div className="loader" />}
          {list && items.length === 0 && (
            <div className="xp-empty">
              <InboxIcon size={32} />
              <strong>{query ? 'Nothing matches' : 'Nothing here yet'}</strong>
              {query ? 'Try other words.' : 'What explorers send from the app shows here.'}
            </div>
          )}
          {items.map((f) => (
            <button type="button" key={f.id} className={`mbx-row ${selectedId === f.id ? 'active' : ''} ${f.status === 'new' ? 'unread' : ''}`} onClick={() => open(f.id)}>
              <Avatar name={f.explorer?.name} email={f.explorer?.email} />
              <div className="mbx-row-main">
                <div className="mbx-row-top">
                  <span className="mbx-row-who">{f.explorer?.name || 'Deleted explorer'}</span>
                  <span className="mbx-row-time" title={formatDateTime(f.created_at)}>{formatWhen(f.created_at)}</span>
                </div>
                <div className="mbx-row-subject">
                  {f.kind === 'quick' ? `${f.ref_label || FEATURE_LABELS[f.feature] || 'Rating'}` : (f.text || '')}
                </div>
                <div className="mbx-row-tags">
                  <TypeChip type={f.type} />
                  {f.kind === 'quick' && f.reasons?.length > 0 && <span className="mbx-chip">{f.reasons.map((r) => REASONS[r] || r).join(', ')}</span>}
                  {f.screenshots > 0 && <span className="mbx-chip">{f.screenshots} {f.screenshots === 1 ? 'picture' : 'pictures'}</span>}
                  {f.status !== 'new' && <StatusChip status={f.status} />}
                </div>
              </div>
              {f.status === 'new' && <span className="mbx-unread-dot" title="New" />}
            </button>
          ))}
          {list?.has_more && (
            <div className="mail-more">
              <button className="btn btn-ghost btn-sm" onClick={loadMore} disabled={loadingMore}>{loadingMore ? 'Loading…' : 'Load older'}</button>
            </div>
          )}
        </div>
      </section>

      <section className="mbx-read" aria-label="Feedback item">
        {!selectedId && (
          <div className="xp-empty">
            <MegaphoneIcon size={36} />
            <strong>Select feedback to read it</strong>
            Opening a new item marks it as seen.
          </div>
        )}
        {selectedId && !item && !itemError && <div className="loader" />}
        {selectedId && itemError && (
          <div className="xp-empty">
            <button type="button" className="mbx-back" onClick={close}>← All feedback</button>
            <strong>Couldn&apos;t open this</strong>{itemError}
          </div>
        )}
        {item && (
          <>
            <div className="mbx-read-bar">
              <button type="button" className="mbx-back" onClick={close}>← All feedback</button>
              <TypeChip type={item.type} />
              <span className="fb-muted">{formatDateTime(item.created_at)}</span>
              <span className="mbx-spacer" />
              <span className="fb-muted">Status</span>
              <select className="xp-select" value={item.status} onChange={(e) => setStatus(e.target.value)} aria-label="Status">
                {STATUSES.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
              </select>
            </div>

            <div className="mbx-read-scroll">
              <div className="mbx-from">
                <Avatar name={explorer?.name} email={explorer?.email} size={44} />
                <div className="mbx-from-main">
                  <div className="mbx-from-name"><b>{explorer?.name || 'Deleted explorer'}</b>{explorer?.email && <span>&lt;{explorer.email}&gt;</span>}</div>
                  <div className="mbx-from-line">
                    {item.country && <>{flag(item.country)} {countryName(item.country)} · </>}
                    {explorer?.joined && <>explorer since {formatDate(explorer.joined)}</>}
                  </div>
                </div>
              </div>

              {item.kind === 'quick' ? (
                <div className="fb-quick">
                  <div className="fb-quick-head">
                    <TypeChip type={item.type} />
                    <b>{item.ref_label || FEATURE_LABELS[item.feature]}</b>
                    <span className="fb-muted">{FEATURE_LABELS[item.feature]}</span>
                  </div>
                  {item.reasons?.length > 0
                    ? <div className="fb-reasons">{item.reasons.map((r) => <span key={r} className="fb-chip tone-red">{REASONS[r] || r}</span>)}</div>
                    : <div className="fb-muted">No reason picked.</div>}
                </div>
              ) : (
                <div className="fb-text">{item.text}</div>
              )}

              {item.screenshots > 0 && (
                <div className="fb-shots">
                  {Array.from({ length: item.screenshots }, (_, i) => (
                    <Shot key={`${item.id}-${i}`} feedbackId={item.id} index={i} onOpen={setLightbox} />
                  ))}
                </div>
              )}

              <div className="fb-meta">
                {[
                  // A quick rating's card above already says what it is about.
                  ['About', item.kind === 'message' && item.ref_label ? `${item.ref_label}${item.feature ? ` · ${FEATURE_LABELS[item.feature]}` : ''}` : null],
                  ['Sent from', item.kind === 'message' ? (SCREENS[item.source_screen] || item.source_screen) : null],
                  ['App', item.app_version ? `${item.app_version}${item.platform ? ` · ${item.platform}` : ''}` : item.platform],
                  ['Phone', item.os_version],
                ].filter(([, v]) => v).map(([k, v]) => (
                  <div key={k}><span>{k}</span><b>{v}</b></div>
                ))}
              </div>

              {item.replies?.length > 0 && (
                <div className="fb-replies">
                  {item.replies.map((r, i) => (
                    <div key={i} className="fb-reply">
                      <div className="fb-reply-head"><b>{r.by === 'admin' ? 'Admin' : r.by}</b> replied · {formatDateTime(r.at)}
                        <span className="fb-muted"> · {[r.sent?.bell && 'app', r.sent?.push && 'push', r.sent?.email && 'email'].filter(Boolean).join(', ') || 'not delivered'}</span>
                      </div>
                      <div>{r.text}</div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {item.kind === 'message' && (item.can_reply ? (
              <form className={`mbx-quick ${reply ? 'open' : ''}`} onSubmit={sendReply}>
                <textarea rows={reply ? Math.min(8, Math.max(3, reply.split('\n').length + 1)) : 2} value={reply}
                  onChange={(e) => setReply(e.target.value)}
                  placeholder={`Reply to ${explorer?.name?.split(/\s+/)[0] || 'the explorer'}… (app notification + email)`} aria-label="Reply" />
                <div className="mbx-quick-actions">
                  <button type="submit" className="btn btn-primary btn-sm" disabled={sending || reply.trim().length < 2}>
                    <SendIcon size={14} /> {sending ? 'Sending…' : 'Send reply'}
                  </button>
                </div>
              </form>
            ) : (
              <div className="fb-noreply">This explorer asked not to be contacted, so there&apos;s no reply box.</div>
            ))}
          </>
        )}
      </section>

      {lightbox && (
        <div className="fb-lightbox" onClick={() => setLightbox(null)} role="presentation">
          <img src={lightbox} alt="Screenshot" />
          <button type="button" className="fb-lightbox-close" onClick={() => setLightbox(null)} title="Close"><CrossIcon size={20} /></button>
        </div>
      )}
    </div>
  );
}

const TABS = [
  { key: 'messages', label: 'Messages', Icon: InboxIcon },
  { key: 'results', label: 'Survey results', Icon: BarChartIcon },
  { key: 'settings', label: 'Survey settings', Icon: SlidersIcon },
];

export default function Feedback() {
  const [tab, setTab] = useState('messages');
  const [counts, setCounts] = useState(null);
  const [toast, notify] = useToast(3500);
  const [countTicks, setCountTicks] = useState(0);

  useEffect(() => {
    apiGet('/admin/feedback/counts').then(setCounts).catch(() => {});
  }, [countTicks]);

  const changed = useCallback(() => { setCountTicks((n) => n + 1); notifyFeedbackChanged(); }, []);

  return (
    <div>
      <Toast toast={toast} />
      <div className="xp-tabs fb-tabs">
        {TABS.map(({ key, label, Icon }) => (
          <button type="button" key={key} className={`xp-tab ${tab === key ? 'active' : ''}`} onClick={() => setTab(key)}>
            <Icon size={15} /> {label}
            {key === 'messages' && counts?.new > 0 && <span className="fb-tab-count">{counts.new}</span>}
          </button>
        ))}
      </div>
      {tab === 'messages' && <Messages counts={counts} onChanged={changed} notify={notify} />}
      {tab === 'results' && <SurveyResults notify={notify} onCreate={() => setTab('settings')} />}
      {tab === 'settings' && <SurveySettings notify={notify} />}
    </div>
  );
}
