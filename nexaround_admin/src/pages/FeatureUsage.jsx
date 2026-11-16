import { useRef, useState } from 'react';
import { useApi } from '../api';
import { Badge, EmptyState, PageError, PageLoading } from '../components/Kit';
import { RefreshIcon, SmartphoneIcon, TrendingUpIcon } from '../components/Icons';

const PERIODS = [7, 30, 90];
// How many columns share one x-axis label, per period length.
const LABEL_EVERY = { 7: 1, 30: 5, 90: 15 };
const PLOT_HEIGHT = 180;
const TIP_WIDTH = 210;

/** 'YYYY-MM-DD' (a Sri Lanka date from the API) → a label. */
function formatDay(isoDate, options) {
  const [y, m, d] = isoDate.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d)).toLocaleDateString('en-US', { ...options, timeZone: 'UTC' });
}

function plural(n, one, many) {
  return `${n.toLocaleString()} ${n === 1 ? one : many}`;
}

function percent(part, whole) {
  if (!whole) return 0;
  const p = (part / whole) * 100;
  return p > 0 && p < 1 ? Math.round(p * 10) / 10 : Math.round(p);
}

/** Change against the previous period of the same length. */
function change(curr, prev) {
  if (!prev) return curr ? { text: 'New', tone: 'up' } : null;
  const pct = Math.round(((curr - prev) / prev) * 100);
  return { text: `${pct > 0 ? '+' : ''}${pct}%`, tone: pct > 0 ? 'up' : pct < 0 ? 'down' : '' };
}

/** Whole-number axis ticks: the smallest 1/2/5 step that needs five steps or fewer. */
function axisTicks(max) {
  const mag = Math.max(1, 10 ** Math.floor(Math.log10(max / 5)));
  const step = [1, 2, 5, 10].map((s) => s * mag).find((s) => Math.ceil(max / s) <= 5);
  return Array.from({ length: Math.ceil(max / step) + 1 }, (_, i) => i * step);
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

/** Explorers per day for one feature. Hover or focus a column for its numbers. */
function DailyChart({ days, values, active, label, period }) {
  const plotRef = useRef(null);
  const [hover, setHover] = useState(null); // { i, width }
  const show = (i) => setHover({ i, width: plotRef.current?.offsetWidth || 0 });
  const ticks = axisTicks(Math.max(...values, 1));
  const top = ticks[ticks.length - 1];
  const last = days.length - 1;
  const peak = values.indexOf(Math.max(...values));
  const every = LABEL_EVERY[period] || 5;

  const i = hover?.i;
  let tipLeft = 0;
  if (i != null) {
    // Beside the hovered column so its bar stays visible; over the plot only
    // when neither side has room.
    const col = hover.width / days.length;
    const right = (i + 1) * col + 8;
    const left = i * col - 8 - TIP_WIDTH;
    if (right + TIP_WIDTH <= hover.width && (i < days.length / 2 || left < 0)) tipLeft = right;
    else if (left >= 0) tipLeft = left;
    else tipLeft = Math.min(Math.max((i + 0.5) * col - TIP_WIDTH / 2, 0), Math.max(hover.width - TIP_WIDTH, 0));
  }
  const dayTitle = (k) => (k === last ? 'Today so far' : formatDay(days[k], { weekday: 'short', month: 'short', day: 'numeric' }));

  return (
    <div className="activity-chart" onMouseLeave={() => setHover(null)}>
      <div className="activity-axis" style={{ height: PLOT_HEIGHT }} aria-hidden="true">
        {ticks.map((t) => <span key={t} style={{ bottom: `${(t / top) * 100}%` }}>{t.toLocaleString()}</span>)}
      </div>
      <div className="activity-plot" ref={plotRef}>
        <div className="activity-grid" style={{ height: PLOT_HEIGHT }} aria-hidden="true">
          {ticks.map((t) => <div key={t} style={{ bottom: `${(t / top) * 100}%` }} />)}
        </div>
        <div className="activity-columns" style={{ height: PLOT_HEIGHT }}>
          {days.map((d, k) => (
            <button
              key={d}
              type="button"
              className={`activity-col${i === k ? ' hovered' : ''}`}
              onMouseEnter={() => show(k)}
              onFocus={() => show(k)}
              onBlur={() => setHover(null)}
              aria-label={`${dayTitle(k)}: ${plural(values[k], 'explorer', 'explorers')} used ${label}, of ${plural(active[k], 'active explorer', 'active explorers')}`}
            >
              {(k === peak || k === last) && values[k] > 0 && (
                <span className="activity-cap" style={{ bottom: `calc(${(values[k] / top) * 100}% + 4px)` }}>
                  {values[k].toLocaleString()}
                </span>
              )}
              <span
                className={`activity-bar${k === last ? ' current' : ''}`}
                style={{ height: values[k] ? `max(3px, ${(values[k] / top) * 100}%)` : 0 }}
              />
            </button>
          ))}
        </div>
        <div className="activity-xlabels" aria-hidden="true">
          {days.map((d, k) => (
            <span key={d} className={k === last ? 'current' : ''}>
              {(last - k) % every === 0 ? formatDay(d, { month: 'short', day: 'numeric' }) : ''}
            </span>
          ))}
        </div>
        {i != null && (
          <div className="activity-tooltip" role="status" style={{ left: tipLeft, width: TIP_WIDTH }}>
            <div className="activity-tooltip-title">{dayTitle(i)}</div>
            <div className="activity-tooltip-value">
              <strong>{values[i].toLocaleString()}</strong> {values[i] === 1 ? 'explorer' : 'explorers'}
            </div>
            <dl>
              <dt>Active explorers</dt><dd>{active[i].toLocaleString()}</dd>
              <dt>Share</dt><dd>{active[i] ? `${percent(values[i], active[i])}%` : '—'}</dd>
            </dl>
          </div>
        )}
      </div>
    </div>
  );
}

/** Features ranked by explorers; a row picks the feature the trend shows. */
function FeatureRanking({ features, total, selected, onSelect, period }) {
  const max = Math.max(...features.map((f) => f.users), 1);
  return (
    <ol className="fu-rank">
      {features.map((f) => {
        const delta = change(f.users, f.prev_users);
        return (
          <li key={f.key}>
            <button
              type="button"
              className={`fu-rank-row${selected === f.key ? ' selected' : ''}`}
              onClick={() => onSelect(f.key)}
              aria-pressed={selected === f.key}
              title={`Show ${f.label} per day`}
            >
              <span className="fu-rank-name">{f.label}</span>
              <span className="fu-rank-value">
                <strong>{f.users.toLocaleString()}</strong>
                <small>{percent(f.users, total)}%</small>
              </span>
              <span className="fu-rank-track" aria-hidden="true">
                <span className="fu-rank-bar" style={{ width: f.users ? `max(4px, ${(f.users / max) * 100}%)` : 0 }} />
              </span>
              <span className="fu-rank-meta">
                {[
                  f.open_users > 0 && `${f.open_users.toLocaleString()} opened it`,
                  f.action_users > 0 && `${f.action_users.toLocaleString()} did something`,
                ].filter(Boolean).join(' · ')}
                {delta && (
                  <span className={`fu-change ${delta.tone}`} title={`${f.prev_users.toLocaleString()} in the previous ${period} days`}>
                    {delta.text}
                  </span>
                )}
              </span>
            </button>
          </li>
        );
      })}
    </ol>
  );
}

/**
 * Which app features explorers use, for the TL and marketing. Every number is
 * unique explorers in Sri Lanka days: someone who opened a feature's screen
 * for 5+ seconds, or finished something in it (a plan, a search, a message, a
 * request, a post). API requests are not counted - the app loads data in the
 * background, so they overstate use.
 */
export default function FeatureUsage() {
  const [days, setDays] = useState(30);
  const [picked, setPicked] = useState(null);
  const { data, loading, error, refetch } = useApi(`/admin/feature-usage?days=${days}`);

  if (error && !data) return <PageError error={error} onRetry={refetch} />;
  if (!data) return <PageLoading />;

  const period = data.days.length;
  const first = data.days[0];
  const lastDay = data.days[period - 1];
  const range = `${formatDay(first, { month: 'short', day: 'numeric' })} – ${formatDay(lastDay, { month: 'short', day: 'numeric', year: 'numeric' })}`;
  const updatedAt = new Date(data.generated_at).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', timeZone: 'Asia/Colombo' });
  const shown = data.features.filter((f) => f.users > 0);
  const selected = shown.find((f) => f.key === picked) || shown[0];
  const active = change(data.active_explorers, data.prev_active_explorers);
  const signups = change(data.new_signups, data.prev_new_signups);
  const coverage = percent(data.reporting_explorers, data.active_explorers);
  const actions = data.actions
    .filter((a) => a.count || a.prev_count)
    .sort((a, b) => b.count - a.count || b.prev_count - a.prev_count);
  const labelOf = Object.fromEntries(data.features.map((f) => [f.key, f.label]));

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
              {p} days
            </button>
          ))}
        </div>
        <span className="fu-range">{range} · Sri Lanka time</span>
        <div className="fu-toolbar-right">
          {error && <span className="fu-error">Refresh failed: {error}</span>}
          <Badge tone="ghost">Updated {updatedAt}</Badge>
          <button type="button" className="filter-sort-btn" onClick={refetch} disabled={loading}>
            <RefreshIcon size={13} style={{ animation: loading ? 'spin 1s linear infinite' : 'none' }} />
            <span>{loading ? 'Refreshing…' : 'Refresh'}</span>
          </button>
        </div>
      </div>

      <div className="activity-kpis fu-kpis">
        <Kpi label="Explorers" value={data.explorers.toLocaleString()} note="Active, or did something in a feature" />
        <Kpi
          label="Active explorers"
          value={data.active_explorers.toLocaleString()}
          note={active ? `${active.text} vs previous ${period} days` : `${data.min_visit_seconds}+ second visits`}
          trend={active?.tone}
        />
        <Kpi
          label="New sign-ups"
          value={data.new_signups.toLocaleString()}
          note={signups ? `${signups.text} vs previous ${period} days` : 'Nothing to compare with yet'}
          trend={signups?.tone}
        />
        <Kpi
          label="Screen reports"
          value={`${coverage}%`}
          note={data.reporting_explorers
            ? `${plural(data.reporting_explorers, 'active explorer is', 'explorers are')} on the new app`
            : 'Start with the next app update'}
        />
      </div>

      {data.reporting_explorers === 0 && (
        <div className="fu-notice">
          <SmartphoneIcon size={16} />
          <span>
            Screen opens arrive with the next app update. Until then, features count explorers who <strong>did
            something</strong> in them (plans, searches, messages, trips, requests, posts), so screens people only
            browse, like Experiences, Museums or the AR camera, show low or not at all.
          </span>
        </div>
      )}

      {shown.length === 0 ? (
        <EmptyState icon={<TrendingUpIcon size={28} />} title="No feature activity in this period" />
      ) : (
        <div className="fu-grid">
          <section className="card fu-card" aria-labelledby="fu-rank-title">
            <div className="fu-card-head">
              <h2 id="fu-rank-title">Most used features</h2>
              <p>Explorers who used each feature · % of all {data.explorers.toLocaleString()} explorers · change vs previous {period} days</p>
            </div>
            <FeatureRanking features={shown} total={data.explorers} selected={selected.key} onSelect={setPicked} period={period} />
          </section>

          <section className="card fu-card fu-sticky" aria-labelledby="fu-trend-title">
            <div className="fu-card-head">
              <h2 id="fu-trend-title">{selected.label} per day</h2>
              <p>Explorers who used it each day. Pick a feature in the list to see it here.</p>
            </div>
            <DailyChart
              key={`${selected.key}-${period}`}
              days={data.days}
              values={selected.daily}
              active={data.active_daily}
              label={selected.label}
              period={period}
            />
            <details className="fu-table-toggle">
              <summary>Daily numbers</summary>
              <div className="table-wrap">
                <table className="fu-table">
                  <thead>
                    <tr><th>Day</th><th className="num">{selected.label}</th><th className="num">Active explorers</th></tr>
                  </thead>
                  <tbody>
                    {data.days.map((d, k) => (
                      <tr key={d}>
                        <td>{formatDay(d, { weekday: 'short', month: 'short', day: 'numeric' })}</td>
                        <td className="num">{selected.daily[k].toLocaleString()}</td>
                        <td className="num">{data.active_daily[k].toLocaleString()}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </details>
          </section>
        </div>
      )}

      <div className="fu-grid">
        <section className="card fu-card" aria-labelledby="fu-actions-title">
          <div className="fu-card-head">
            <h2 id="fu-actions-title">What explorers did</h2>
            <p>Saved actions in the last {period} days</p>
          </div>
          {actions.length === 0 ? (
            <EmptyState>No actions in this period.</EmptyState>
          ) : (
            <div className="table-wrap">
              <table className="fu-table">
                <thead>
                  <tr><th>Action</th><th>Feature</th><th className="num">Times</th><th className="num">Explorers</th><th className="num">vs previous</th></tr>
                </thead>
                <tbody>
                  {actions.map((a) => {
                    const delta = change(a.count, a.prev_count);
                    return (
                      <tr key={a.key}>
                        <td>{a.label}</td>
                        <td className="muted">{labelOf[a.feature] || a.feature}</td>
                        <td className="num">{a.count.toLocaleString()}</td>
                        <td className="num">{a.users.toLocaleString()}</td>
                        <td className="num">
                          {delta ? <span className={`fu-change ${delta.tone}`} title={`${a.prev_count.toLocaleString()} in the previous ${period} days`}>{delta.text}</span> : '—'}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </section>

        <section className="card fu-card" aria-labelledby="fu-funnel-title">
          <div className="fu-card-head">
            <h2 id="fu-funnel-title">Opened → used</h2>
            <p>Of the explorers who opened a feature, how many went on to use it</p>
          </div>
          {data.funnels.length === 0 ? (
            <EmptyState>Shows once screen opens arrive with the next app update.</EmptyState>
          ) : (
            <ul className="fu-funnels">
              {data.funnels.map((f) => (
                <li key={f.feature}>
                  <div className="fu-funnel-text">
                    <span className="fu-funnel-name">{f.label}</span>
                    <span className="fu-funnel-detail">
                      {plural(f.opened, 'explorer', 'explorers')} opened it · {f.acted.toLocaleString()} {f.action_label}
                    </span>
                  </div>
                  <span className="fu-funnel-pct">{percent(f.acted, f.opened)}%</span>
                  <span className="fu-rank-track" aria-hidden="true">
                    <span className="fu-rank-bar" style={{ width: f.acted ? `max(4px, ${percent(f.acted, f.opened)}%)` : 0 }} />
                  </span>
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>

      <p className="fu-footnote">
        An explorer counts once per feature in the period: they opened its screen for 5+ seconds, or did something in it.
        API requests are not counted, because the app also loads data in the background. Suspended explorers and the
        official TravelByte account are left out. Active explorers follow the Users page: a visit of {data.min_visit_seconds}+ seconds.
      </p>
    </div>
  );
}
