import { useRef, useState } from 'react';
import { useApi } from '../api';
import { Badge, EmptyState, PageError, PageLoading } from '../components/Kit';
import { RefreshIcon, SmartphoneIcon } from '../components/Icons';

const PERIODS = [7, 30, 90];
// How many columns share one x-axis label, per period length.
const LABEL_EVERY = { 7: 1, 30: 5, 90: 15 };
const PLOT_HEIGHT = 180;
const TIP_WIDTH = 220;
// Below this many explorers on the latest app, screen shares get a caution.
const SMALL_SAMPLE = 100;

/** 'YYYY-MM-DD' (a Sri Lanka date from the API) → '16 Nov' (or with options). */
function formatDay(isoDate, options = { day: 'numeric', month: 'short' }) {
  const [y, m, d] = isoDate.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d)).toLocaleDateString('en-GB', { ...options, timeZone: 'UTC' });
}

function addDays(isoDate, n) {
  const [y, m, d] = isoDate.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

function people(n) {
  return `${n.toLocaleString()} ${n === 1 ? 'person' : 'people'}`;
}

function times(n) {
  return `${n.toLocaleString()} ${n === 1 ? 'time' : 'times'}`;
}

function percent(share) {
  const p = share * 100;
  return `${p > 0 && p < 1 ? p.toFixed(1) : Math.round(p)}%`;
}

/** "Up from 92", "Down from 26" or "Same as before"; null when there is nothing fair to compare with. */
function versus(curr, prev, period, format = (n) => n.toLocaleString()) {
  if (prev == null) return null;
  const before = `in the ${period} days before`;
  if (prev === 0 && curr > 0) return { tone: 'up', text: `↑ None ${before}` };
  if (curr > prev) return { tone: 'up', text: `↑ Up from ${format(prev)} ${before}` };
  if (curr < prev) return { tone: 'down', text: `↓ Down from ${format(prev)} ${before}` };
  return { tone: '', text: `Same as ${before}` };
}

/** Whole-number axis ticks: the smallest 1/2/5 step that needs five steps or fewer. */
function axisTicks(max) {
  const mag = Math.max(1, 10 ** Math.floor(Math.log10(max / 5)));
  const step = [1, 2, 5, 10].map((s) => s * mag).find((s) => Math.ceil(max / s) <= 5);
  return Array.from({ length: Math.ceil(max / step) + 1 }, (_, i) => i * step);
}

function Tile({ label, value, note, compare }) {
  return (
    <div className="activity-kpi">
      <span className="activity-kpi-label">{label}</span>
      <span className="activity-kpi-value">{value}</span>
      <span className="activity-kpi-note">{note}</span>
      {compare && <span className={`activity-kpi-note ${compare.tone}`}>{compare.text}</span>}
    </div>
  );
}

/**
 * People per day for one screen or action. Days before it was counted show as
 * a grey "not counted yet" band, never as zero. Hover or focus a day for its
 * numbers; the table below the chart has every value too.
 */
function DailyChart({ days, values, context, contextLabel, period }) {
  const plotRef = useRef(null);
  const [hover, setHover] = useState(null); // { i, width }
  const show = (i) => setHover({ i, width: plotRef.current?.offsetWidth || 0 });
  const counted = values.filter((v) => v != null);
  const ticks = axisTicks(Math.max(...counted, 1));
  const top = ticks[ticks.length - 1];
  const last = days.length - 1;
  const firstCounted = values.findIndex((v) => v != null);
  const peak = values.indexOf(Math.max(...counted, 0));
  const every = LABEL_EVERY[period] || 5;
  const dayTitle = (k) => (k === last ? 'Today so far' : formatDay(days[k], { weekday: 'short', day: 'numeric', month: 'short' }));

  const i = hover?.i;
  let tipLeft = 0;
  if (i != null) {
    // Beside the hovered day so its bar stays visible; over the plot only
    // when neither side has room.
    const col = hover.width / days.length;
    const right = (i + 1) * col + 8;
    const left = i * col - 8 - TIP_WIDTH;
    if (right + TIP_WIDTH <= hover.width && (i < days.length / 2 || left < 0)) tipLeft = right;
    else if (left >= 0) tipLeft = left;
    else tipLeft = Math.min(Math.max((i + 0.5) * col - TIP_WIDTH / 2, 0), Math.max(hover.width - TIP_WIDTH, 0));
  }

  return (
    <div className="activity-chart" onMouseLeave={() => setHover(null)}>
      <div className="activity-axis" style={{ height: PLOT_HEIGHT }} aria-hidden="true">
        {ticks.map((t) => <span key={t} style={{ bottom: `${(t / top) * 100}%` }}>{t.toLocaleString()}</span>)}
      </div>
      <div className="activity-plot" ref={plotRef}>
        <div className="activity-grid" style={{ height: PLOT_HEIGHT }} aria-hidden="true">
          {ticks.map((t) => <div key={t} style={{ bottom: `${(t / top) * 100}%` }} />)}
        </div>
        {firstCounted > 0 && (
          <div
            className="fu-uncounted"
            style={{ height: PLOT_HEIGHT, width: `${(firstCounted / days.length) * 100}%` }}
            aria-hidden="true"
          >
            {firstCounted / days.length >= 0.18 && <span>Not counted yet</span>}
          </div>
        )}
        <div className="activity-columns" style={{ height: PLOT_HEIGHT }}>
          {days.map((d, k) => {
            const v = values[k];
            return (
              <button
                key={d}
                type="button"
                className={`activity-col${i === k ? ' hovered' : ''}`}
                onMouseEnter={() => show(k)}
                onFocus={() => show(k)}
                onBlur={() => setHover(null)}
                aria-label={v == null ? `${dayTitle(k)}: not counted yet` : `${dayTitle(k)}: ${people(v)}`}
              >
                {v != null && (k === peak || k === last) && v > 0 && (
                  <span className="activity-cap" style={{ bottom: `calc(${(v / top) * 100}% + 4px)` }}>{v.toLocaleString()}</span>
                )}
                <span
                  className={`activity-bar${k === last ? ' current' : ''}`}
                  style={{ height: v ? `max(3px, ${(v / top) * 100}%)` : 0 }}
                />
              </button>
            );
          })}
        </div>
        <div className="activity-xlabels" aria-hidden="true">
          {days.map((d, k) => (
            <span key={d} className={k === last ? 'current' : ''}>
              {(last - k) % every === 0 ? formatDay(d) : ''}
            </span>
          ))}
        </div>
        {i != null && (
          <div className="activity-tooltip" role="status" style={{ left: tipLeft, width: TIP_WIDTH }}>
            <div className="activity-tooltip-title">{dayTitle(i)}</div>
            {values[i] == null ? (
              <div className="activity-tooltip-value">Not counted yet on this day</div>
            ) : (
              <>
                <div className="activity-tooltip-value"><strong>{values[i].toLocaleString()}</strong> {values[i] === 1 ? 'person' : 'people'}</div>
                {context?.[i] != null && (
                  <dl><dt>{contextLabel}</dt><dd>{context[i].toLocaleString()}</dd></dl>
                )}
              </>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

/** A ranked list of screens or actions; clicking a row shows it in the chart. */
function Ranking({ rows, selected, onSelect }) {
  return (
    <ol className="fu-rank">
      {rows.map((r) => (
        <li key={r.id}>
          <button
            type="button"
            className={`fu-rank-row${selected === r.id ? ' selected' : ''}`}
            onClick={() => onSelect(r.id)}
            aria-pressed={selected === r.id}
            title="Show this per day in the chart"
          >
            <span className="fu-rank-name">
              {r.label}
              {r.where && <small className="fu-rank-where">{r.where}</small>}
            </span>
            <span className="fu-rank-value">
              <strong>{r.value}</strong>
              {r.side && <small>{r.side}</small>}
            </span>
            <span className="fu-rank-track" aria-hidden="true">
              <span className="fu-rank-bar" style={{ width: r.bar ? `max(4px, ${r.bar * 100}%)` : 0 }} />
            </span>
            {(r.compare || r.note) && (
              <span className="fu-rank-meta">
                {r.compare && <span className={`fu-change ${r.compare.tone}`}>{r.compare.text}</span>}
                {r.note && <span>{r.note}</span>}
              </span>
            )}
          </button>
        </li>
      ))}
    </ol>
  );
}

/**
 * Which parts of the app explorers use, written for anyone on the team. Every
 * number counts people, not taps. Screens come from explorers whose app
 * reports them (the latest version); actions such as searches, plans and
 * messages are saved for every explorer. Days before something was counted
 * are shown as "not counted yet", never as zero, and a change against the
 * previous period only appears when both periods were counted in full.
 */
export default function FeatureUsage() {
  const [days, setDays] = useState(30);
  const [picked, setPicked] = useState(null);
  const chartRef = useRef(null);
  const { data, loading, error, refetch } = useApi(`/admin/feature-usage?days=${days}`);

  if (error && !data) return <PageError error={error} onRetry={refetch} />;
  if (!data) return <PageLoading />;

  const period = data.days.length;
  const first = data.days[0];
  const range = `${formatDay(first)} – ${formatDay(data.days[period - 1], { day: 'numeric', month: 'short', year: 'numeric' })}`;
  const updatedAt = new Date(data.generated_at).toLocaleTimeString('en-GB', { hour: 'numeric', minute: '2-digit', timeZone: 'Asia/Colombo' });
  const reporting = data.reporting_explorers;
  const screensSince = data.screens_since;
  // Screen comparisons need a full previous period of screen counts.
  const screensCompareFrom = screensSince && data.screens.every((s) => s.prev_users == null)
    ? addDays(screensSince, 2 * period - 1) : null;
  const maxActionPeople = Math.max(...data.actions.map((a) => a.users), 1);

  const screenRows = data.screens.map((s) => ({
    id: `screen:${s.key}`,
    label: s.label,
    value: people(s.users),
    side: percent(s.share),
    bar: s.share,
    compare: s.prev_share == null ? null : versus(Math.round(s.share * 100), Math.round(s.prev_share * 100), period, (n) => `${n}%`),
  }));
  const actionRows = data.actions.map((a) => ({
    id: `action:${a.key}`,
    label: a.label,
    where: a.feature_label,
    value: people(a.users),
    side: times(a.count),
    bar: a.users / maxActionPeople,
    compare: versus(a.users, a.prev_users, period, people),
    note: a.prev_users == null && a.counted_since ? `Counted since ${formatDay(a.counted_since, { day: 'numeric', month: 'short', year: 'numeric' })}` : null,
  }));

  // The chart shows the picked row, else the most opened screen, else the top action.
  const options = [
    ...data.screens.map((s) => ({ id: `screen:${s.key}`, title: `${s.label}: people who opened it`, values: s.daily, context: data.reporting_daily, contextLabel: 'Explorers on the latest app' })),
    ...data.actions.map((a) => ({ id: `action:${a.key}`, title: `${a.label}: people per day`, values: a.daily, context: data.active_daily, contextLabel: 'Active explorers that day' })),
  ];
  const screensCounted = data.reporting_daily.filter((v) => v != null).length;
  const fallback = screensCounted * 2 >= period ? options[0] : options.find((o) => o.id.startsWith('action:')) || options[0];
  const chosen = options.find((o) => o.id === picked) || fallback;
  const select = (id) => {
    setPicked(id);
    chartRef.current?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  };

  return (
    <div className="fu-page" style={{ opacity: loading ? 0.6 : 1, transition: 'opacity 0.2s' }}>
      <div className="xp-toolbar fu-toolbar">
        <div className="seg" role="tablist" aria-label="Period">
          {PERIODS.map((p) => (
            <button
              key={p}
              type="button"
              role="tab"
              aria-selected={days === p}
              className={`seg-btn ${days === p ? 'active' : ''}`}
              onClick={() => setDays(p)}
            >
              Last {p} days
            </button>
          ))}
        </div>
        <span className="fu-range">{range}</span>
        <div className="fu-toolbar-right">
          {error && <span className="fu-error">Could not refresh: {error}</span>}
          <Badge tone="ghost">Updated {updatedAt}</Badge>
          <button type="button" className="filter-sort-btn" onClick={refetch} disabled={loading}>
            <RefreshIcon size={13} style={{ animation: loading ? 'spin 1s linear infinite' : 'none' }} />
            <span>{loading ? 'Refreshing…' : 'Refresh'}</span>
          </button>
        </div>
      </div>

      <p className="fu-intro">
        Which parts of the app people use. Every number counts <strong>people, not taps</strong>: someone who opens
        a screen ten times counts once.
      </p>

      <div className="activity-kpis fu-kpis">
        <Tile
          label="Active explorers"
          value={data.active_explorers.toLocaleString()}
          note={`Spent ${data.min_visit_seconds}+ seconds in the app`}
          compare={versus(data.active_explorers, data.prev_active_explorers, period)}
        />
        <Tile
          label="New sign-ups"
          value={data.new_signups.toLocaleString()}
          note="New accounts created"
          compare={versus(data.new_signups, data.prev_new_signups, period)}
        />
        <Tile
          label="Explorers on the latest app"
          value={reporting.toLocaleString()}
          note={screensSince
            ? `Their app reports which screens they open. Counting since ${formatDay(screensSince).replace(' ', '\u00a0')}.`
            : 'Screen counts start when explorers update the app'}
        />
      </div>

      <section className="card fu-card" ref={chartRef} aria-labelledby="fu-chart-title">
        {chosen ? (
          <>
            <div className="fu-card-head">
              <h2 id="fu-chart-title">{chosen.title}</h2>
              <p>Click any row below to see it here. Grey days had not been counted yet.</p>
            </div>
            <DailyChart
              key={`${chosen.id}-${period}`}
              days={data.days}
              values={chosen.values}
              context={chosen.context}
              contextLabel={chosen.contextLabel}
              period={period}
            />
            <details className="fu-table-toggle">
              <summary>Show the numbers for each day</summary>
              <div className="table-wrap">
                <table className="fu-table">
                  <thead>
                    <tr><th>Day</th><th className="num">People</th><th className="num">{chosen.contextLabel}</th></tr>
                  </thead>
                  <tbody>
                    {data.days.map((d, k) => (
                      <tr key={d}>
                        <td>{formatDay(d, { weekday: 'short', day: 'numeric', month: 'short' })}</td>
                        <td className="num">{chosen.values[k] == null ? 'Not counted yet' : chosen.values[k].toLocaleString()}</td>
                        <td className="num">{chosen.context?.[k] == null ? '—' : chosen.context[k].toLocaleString()}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </details>
          </>
        ) : (
          <EmptyState>Nothing was used in this period.</EmptyState>
        )}
      </section>

      <div className="fu-grid">
        <section className="card fu-card" aria-labelledby="fu-screens-title">
          <div className="fu-card-head">
            <h2 id="fu-screens-title">Most opened screens</h2>
            <p>
              {reporting
                ? `Out of the ${people(reporting)} on the latest app, how many opened each screen in the last ${period} days.`
                : `How many people opened each screen in the last ${period} days.`}
            </p>
          </div>
          {reporting > 0 && reporting < SMALL_SAMPLE && (
            <div className="fu-notice">
              <SmartphoneIcon size={16} />
              <span>
                Based on {people(reporting)} so far, because only the latest app version reports screens. These
                shares will become more reliable as more explorers update.
              </span>
            </div>
          )}
          {data.screens.length === 0 ? (
            <EmptyState>Screen counts start when explorers update to the latest app.</EmptyState>
          ) : (
            <>
              <Ranking rows={screenRows} selected={chosen?.id} onSelect={select} />
              {screensCompareFrom && (
                <p className="fu-card-foot">
                  A comparison with the {period} days before appears from {formatDay(screensCompareFrom, { day: 'numeric', month: 'short', year: 'numeric' })},
                  once screens have been counted for long enough.
                </p>
              )}
            </>
          )}
        </section>

        <section className="card fu-card" aria-labelledby="fu-actions-title">
          <div className="fu-card-head">
            <h2 id="fu-actions-title">What people did</h2>
            <p>Things explorers finished in the last {period} days. These count every explorer, on any app version.</p>
          </div>
          {data.actions.length === 0 ? (
            <EmptyState>Nothing was done in this period.</EmptyState>
          ) : (
            <Ranking rows={actionRows} selected={chosen?.id} onSelect={select} />
          )}
        </section>
      </div>

      {data.funnels.length > 0 && (
        <section className="card fu-card" aria-labelledby="fu-funnel-title">
          <div className="fu-card-head">
            <h2 id="fu-funnel-title">Did they go on to use it?</h2>
            <p>Of the people who opened a screen, how many then did something there (latest app only).</p>
          </div>
          <ul className="fu-funnels">
            {data.funnels.map((f) => (
              <li key={f.feature}>
                <div className="fu-funnel-text">
                  <span className="fu-funnel-name">{f.label}</span>
                  <span className="fu-funnel-detail">
                    {people(f.opened)} opened it · {f.acted.toLocaleString()} {f.action_label}
                  </span>
                </div>
                <span className="fu-funnel-pct">{percent(f.acted / f.opened)}</span>
                <span className="fu-rank-track" aria-hidden="true">
                  <span className="fu-rank-bar" style={{ width: f.acted ? `max(4px, ${(f.acted / f.opened) * 100}%)` : 0 }} />
                </span>
              </li>
            ))}
          </ul>
        </section>
      )}

      <details className="card fu-card fu-howto">
        <summary>How these numbers are counted</summary>
        <ul>
          <li><strong>People, not taps.</strong> Each person counts once per screen or action in the period, however often they used it.</li>
          <li><strong>Screens</strong> count when they stay open for at least 5 seconds. Screens that load in the background, or that someone only passes through, don&apos;t count.</li>
          <li>Only the <strong>latest app version</strong> reports screens{screensSince ? ` (since ${formatDay(screensSince, { day: 'numeric', month: 'long', year: 'numeric' })})` : ''}, so screen shares are out of the explorers who have it.</li>
          <li><strong>Actions</strong> (searches, trip plans, messages, booking requests, posts) are saved for everyone, so they include all explorers.</li>
          <li>Each action counts from the first day we have it. <strong>Grey days</strong> in the chart mean &quot;not counted yet&quot;, not zero.</li>
          <li>&quot;Up from&quot; and &quot;Down from&quot; compare with the same number of days just before, and only appear when both periods were counted in full.</li>
          <li><strong>Active explorers</strong> spent at least {data.min_visit_seconds} seconds in the app in one visit, the same rule as the User Management page.</li>
          <li>Suspended accounts and the official TravelByte account are left out. Days follow Sri Lanka time.</li>
        </ul>
      </details>
    </div>
  );
}
