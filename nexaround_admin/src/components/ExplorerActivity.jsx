import { useRef, useState } from 'react';
import { useApi } from '../api';
import { TrendingUpIcon, RefreshIcon } from './Icons';
import { Badge, Loading, EmptyState } from './Kit';

// The three views of /admin/users/activity. `unit` names one bucket, `range`
// the stretch the frequent-explorers ranking covers, `labelEvery` how many
// columns share one x-axis label.
const VIEWS = {
  daily: { tab: 'Daily', unit: 'day', range: 'last 30 days', labelEvery: 5 },
  weekly: { tab: 'Weekly', unit: 'week', range: 'last 12 weeks', labelEvery: 2 },
  monthly: { tab: 'Monthly', unit: 'month', range: 'last 12 months', labelEvery: 1 },
};

const FREQUENT_SHOWN = 5;
const PLOT_HEIGHT = 200;
const TIP_WIDTH = 200;

/** 'YYYY-MM-DD' (a Sri Lanka date from the API) → Date at UTC midnight. */
function toDate(isoDate) {
  const [y, m, d] = isoDate.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}

function formatDate(isoDate, options) {
  return toDate(isoDate).toLocaleDateString('en-US', { ...options, timeZone: 'UTC' });
}

/** Short x-axis label for a bucket start. */
function axisLabel(view, start) {
  return view === 'monthly'
    ? formatDate(start, { month: 'short' })
    : formatDate(start, { month: 'short', day: 'numeric' });
}

/** Full name of a bucket for the tooltip. The last one is still running. */
function bucketTitle(view, start, isCurrent) {
  if (view === 'daily') {
    return isCurrent ? 'Today so far' : formatDate(start, { weekday: 'short', month: 'short', day: 'numeric' });
  }
  if (view === 'weekly') {
    return `Week of ${formatDate(start, { month: 'short', day: 'numeric' })}${isCurrent ? ' (so far)' : ''}`;
  }
  return `${formatDate(start, { month: 'long', year: 'numeric' })}${isCurrent ? ' (so far)' : ''}`;
}

function formatDuration(seconds) {
  if (seconds < 60) return `${seconds}s`;
  const mins = Math.floor(seconds / 60);
  if (mins < 60) return `${mins}m`;
  const hours = Math.floor(mins / 60);
  return hours >= 100 ? `${hours.toLocaleString()}h` : `${hours}h ${mins % 60}m`;
}

function timeAgo(isoStr) {
  const mins = Math.floor((Date.now() - new Date(isoStr).getTime()) / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d ago`;
  return new Date(isoStr).toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'Asia/Colombo' });
}

function plural(n, one, many) {
  return `${n.toLocaleString()} ${n === 1 ? one : many}`;
}

/** Whole-number axis ticks: the smallest 1/2/5 step that needs five steps or fewer. */
function axisTicks(max) {
  const mag = Math.max(1, 10 ** Math.floor(Math.log10(max / 5)));
  const step = [1, 2, 5, 10].map((s) => s * mag).find((s) => Math.ceil(max / s) <= 5);
  return Array.from({ length: Math.ceil(max / step) + 1 }, (_, i) => i * step);
}

/** "+12% vs previous 7 days", or null when there is nothing to compare with. */
function change(curr, prev, days) {
  if (!prev) return null;
  const pct = Math.round(((curr - prev) / prev) * 100);
  return { pct, text: `${pct > 0 ? '+' : ''}${pct}% vs previous ${days} days` };
}

function Kpi({ label, value, note, trend }) {
  return (
    <div className="activity-kpi">
      <span className="activity-kpi-label">{label}</span>
      <span className="activity-kpi-value">{value}</span>
      <span className={`activity-kpi-note${trend ? ` ${trend}` : ''}`}>{note}</span>
    </div>
  );
}

/** Active explorers per bucket. Hover or focus a column for its breakdown. */
function ActivityChart({ view, buckets }) {
  const plotRef = useRef(null);
  const [hover, setHover] = useState(null); // { i, width } — width of the plot in px
  const hovered = hover?.i ?? null;
  const show = (i) => setHover({ i, width: plotRef.current?.offsetWidth || 0 });
  const values = buckets.map((b) => b.active);
  const ticks = axisTicks(Math.max(...values, 1));
  const top = ticks[ticks.length - 1];
  const last = buckets.length - 1;
  const peak = values.indexOf(Math.max(...values));
  const { unit, labelEvery } = VIEWS[view];

  const tip = hovered != null && buckets[hovered];
  let tipLeft = 0;
  if (tip) {
    // Beside the hovered column so its bar stays visible; over the plot only
    // when neither side has room (phone widths).
    const col = hover.width / buckets.length;
    const right = (hovered + 1) * col + 8;
    const left = hovered * col - 8 - TIP_WIDTH;
    const fitsRight = right + TIP_WIDTH <= hover.width;
    const fitsLeft = left >= 0;
    if (fitsRight && (hovered < buckets.length / 2 || !fitsLeft)) tipLeft = right;
    else if (fitsLeft) tipLeft = left;
    else tipLeft = Math.min(Math.max((hovered + 0.5) * col - TIP_WIDTH / 2, 0), Math.max(hover.width - TIP_WIDTH, 0));
  }

  return (
    <div className="activity-chart" onMouseLeave={() => setHover(null)}>
      <div className="activity-axis" style={{ height: PLOT_HEIGHT }} aria-hidden="true">
        {ticks.map((t) => (
          <span key={t} style={{ bottom: `${(t / top) * 100}%` }}>{t.toLocaleString()}</span>
        ))}
      </div>
      <div className="activity-plot" ref={plotRef}>
        <div className="activity-grid" style={{ height: PLOT_HEIGHT }} aria-hidden="true">
          {ticks.map((t) => <div key={t} style={{ bottom: `${(t / top) * 100}%` }} />)}
        </div>

        <div className="activity-columns" style={{ height: PLOT_HEIGHT }}>
          {buckets.map((b, i) => {
            const title = bucketTitle(view, b.start, i === last);
            const returning = b.active - b.new;
            return (
              <button
                key={b.start}
                type="button"
                className={`activity-col${hovered === i ? ' hovered' : ''}`}
                onMouseEnter={() => show(i)}
                onFocus={() => show(i)}
                onBlur={() => setHover(null)}
                aria-label={`${title}: ${plural(b.active, 'active explorer', 'active explorers')}, ${returning} returning, ${b.new} new, ${plural(b.sessions, 'session', 'sessions')}, ${formatDuration(b.app_seconds)} in the app`}
              >
                {(i === peak || i === last) && b.active > 0 && (
                  <span className="activity-cap" style={{ bottom: `calc(${(b.active / top) * 100}% + 4px)` }}>
                    {b.active.toLocaleString()}
                  </span>
                )}
                <span
                  className={`activity-bar${i === last ? ' current' : ''}`}
                  style={{ height: b.active ? `max(3px, ${(b.active / top) * 100}%)` : 0 }}
                />
              </button>
            );
          })}
        </div>

        <div className="activity-xlabels" aria-hidden="true">
          {buckets.map((b, i) => (
            <span key={b.start} className={i === last ? 'current' : ''}>
              {(last - i) % labelEvery === 0 ? axisLabel(view, b.start) : ''}
            </span>
          ))}
        </div>

        {tip && (
          <div
            className="activity-tooltip"
            role="status"
            style={{ left: tipLeft, width: TIP_WIDTH }}
          >
            <div className="activity-tooltip-title">{bucketTitle(view, tip.start, hovered === last)}</div>
            <div className="activity-tooltip-value">
              <strong>{tip.active.toLocaleString()}</strong> active {tip.active === 1 ? 'explorer' : 'explorers'}
            </div>
            <dl>
              <dt>Returning</dt><dd>{(tip.active - tip.new).toLocaleString()}</dd>
              <dt>New this {unit}</dt><dd>{tip.new.toLocaleString()}</dd>
              <dt>App sessions</dt><dd>{tip.sessions.toLocaleString()}</dd>
              <dt>Time in app</dt><dd>{formatDuration(tip.app_seconds)}</dd>
            </dl>
          </div>
        )}
      </div>
    </div>
  );
}

/** Explorers active in the most days / weeks / months of the view's window. */
function FrequentList({ view, top, periods, range }) {
  const [showAll, setShowAll] = useState(false);
  const { unit } = VIEWS[view];
  const shown = showAll ? top : top.slice(0, FREQUENT_SHOWN);

  return (
    <div className="activity-frequent">
      <div className="activity-frequent-head">
        <h3>Most frequent explorers</h3>
        <span>Ranked by {unit}s active, {range}</span>
      </div>
      {top.length === 0 ? (
        <EmptyState>No explorer activity in this period.</EmptyState>
      ) : (
        <ol>
          {shown.map((u) => (
            <li key={u.id}>
              {u.avatar_url
                ? <img src={u.avatar_url} alt="" className="activity-avatar" />
                : <span className="user-avatar activity-avatar">{(u.display_name || 'E')[0].toUpperCase()}</span>}
              <div className="activity-frequent-who">
                <span className="activity-frequent-name" title={u.email}>{u.display_name || 'Explorer'}</span>
                <span className="activity-frequent-meta">
                  {plural(u.sessions, 'session', 'sessions')} · {formatDuration(u.app_seconds)} · {timeAgo(u.last_active_at)}
                </span>
              </div>
              <div className="activity-frequent-score" title={`Active in ${u.active_periods} of ${periods} ${unit}s`}>
                <span>{u.active_periods}<small>/{periods} {unit}s</small></span>
                <div className="activity-meter">
                  <div style={{ width: `${(u.active_periods / periods) * 100}%` }} />
                </div>
              </div>
            </li>
          ))}
        </ol>
      )}
      {top.length > FREQUENT_SHOWN && (
        <button type="button" className="activity-more" onClick={() => setShowAll((v) => !v)}>
          {showAll ? 'Show fewer' : `Show top ${top.length}`}
        </button>
      )}
    </div>
  );
}

/**
 * Daily, weekly and monthly active explorers for the Users page. An explorer
 * counts as active when they opened the app or used a feature that day.
 */
export default function ExplorerActivity() {
  const { data, loading, error, refetch } = useApi('/admin/users/activity');
  const [view, setView] = useState('daily');

  const updatedAt = data && new Date(data.generated_at).toLocaleTimeString('en-US', {
    hour: 'numeric', minute: '2-digit', timeZone: 'Asia/Colombo',
  });

  let body;
  if (!data) {
    body = loading
      ? <Loading>Loading explorer activity…</Loading>
      : <EmptyState>Could not load explorer activity: {error}</EmptyState>;
  } else {
    const week = change(data.last_7d, data.prev_7d, 7);
    const month = change(data.last_30d, data.prev_30d, 30);
    const stickiness = data.last_30d ? Math.round((data.avg_daily_30d / data.last_30d) * 100) : null;
    const all = data[view].buckets;
    // Start at the first day/week/month with any activity; tracking began
    // in May 2026, so the earliest months would only be empty columns.
    const buckets = all.slice(Math.max(0, all.findIndex((b) => b.active > 0)));
    const range = buckets.length < all.length
      ? `since ${axisLabel(view, buckets[0].start)}`
      : VIEWS[view].range;
    const { top } = data[view];

    body = (
      <div style={{ opacity: loading ? 0.6 : 1, transition: 'opacity 0.2s' }}>
        {error && <div className="activity-error">Refresh failed: {error}. Showing the figures from {updatedAt}.</div>}

        <div className="activity-kpis">
          <Kpi label="Active today" value={data.today.toLocaleString()} note={`${data.yesterday.toLocaleString()} yesterday`} />
          <Kpi label="Active · 7 days" value={data.last_7d.toLocaleString()}
            note={week ? week.text : 'Nothing to compare with yet'} trend={week && (week.pct >= 0 ? 'up' : 'down')} />
          <Kpi label="Active · 30 days" value={data.last_30d.toLocaleString()}
            note={month ? month.text : 'Nothing to compare with yet'} trend={month && (month.pct >= 0 ? 'up' : 'down')} />
          <Kpi label="Stickiness" value={stickiness == null ? '—' : `${stickiness}%`}
            note={`Daily average ${data.avg_daily_30d.toLocaleString()} ÷ ${data.last_30d.toLocaleString()}`} />
          <Kpi label="Regulars" value={data.regulars_30d.toLocaleString()}
            note={`Active on ${data.regular_days}+ of the last 30 days`} />
        </div>

        <div className="activity-toolbar">
          <div className="segmented-tabs" role="tablist" aria-label="Activity period">
            {Object.entries(VIEWS).map(([key, v]) => (
              <button
                key={key}
                type="button"
                role="tab"
                aria-selected={view === key}
                className={`segmented-tab ${view === key ? 'active' : ''}`}
                onClick={() => setView(key)}
              >
                {v.tab}
              </button>
            ))}
          </div>
          <span className="activity-toolbar-note">
            Active explorers per {VIEWS[view].unit}, {range}. Hover a column for details.
          </span>
        </div>

        <div className="activity-body">
          <ActivityChart key={view} view={view} buckets={buckets} />
          <FrequentList key={`top-${view}`} view={view} top={top} periods={buckets.length} range={range} />
        </div>
      </div>
    );
  }

  return (
    <section className="card activity-card" aria-labelledby="explorer-activity-title">
      <div className="activity-head">
        <div>
          <h2 id="explorer-activity-title">
            <TrendingUpIcon size={18} style={{ color: 'var(--accent)' }} />
            Explorer activity
          </h2>
          <p>Explorers who opened the app or used a feature · Sri Lanka time</p>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          {updatedAt && <Badge tone="ghost">Updated {updatedAt}</Badge>}
          <button type="button" className="filter-sort-btn" onClick={refetch} disabled={loading} title="Refresh explorer activity">
            <RefreshIcon size={13} style={{ animation: loading ? 'spin 1s linear infinite' : 'none' }} />
            <span>{loading ? 'Refreshing…' : 'Refresh'}</span>
          </button>
        </div>
      </div>
      {body}
    </section>
  );
}
