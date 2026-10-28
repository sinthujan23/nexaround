import { Fragment, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { useApi } from '../api';
import { EmptyState, PageError, PageLoading } from '../components/Kit';
import { TrendingUpIcon } from '../components/Icons';

const PERIODS = [
  { days: 7, label: '7 days' },
  { days: 30, label: '30 days' },
  { days: 90, label: '90 days' },
  { days: 365, label: '1 year' },
  { days: 0, label: 'All time' },
];

const formatDate = (value) => (value
  ? new Date(value).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })
  : '');

/**
 * How often travellers tapped each partner link in the City Tours guides,
 * grouped by partner, for reporting to partners. One tap is one press of a
 * button in the app (a page reloaded in a loop counts at most 30 a minute).
 */
export default function CityTourTaps() {
  const [days, setDays] = useState(30);
  const { data, loading, error, refetch } = useApi(`/admin/city-tours/taps?days=${days}`);

  const groups = useMemo(() => {
    const byPartner = new Map();
    for (const row of data?.rows || []) {
      const key = row.partner === 'experience' ? `experience:${row.partner_name}` : row.partner;
      if (!byPartner.has(key)) byPartner.set(key, { name: row.partner_name, rows: [], total: 0 });
      const g = byPartner.get(key);
      g.rows.push(row);
      g.total += row.taps;
    }
    return [...byPartner.values()].sort((a, b) => b.total - a.total);
  }, [data]);

  if (error && !data) return <PageError error={error} onRetry={refetch} />;

  return (
    <div>
      <div className="xp-toolbar">
        <div className="seg">
          {PERIODS.map((p) => (
            <button key={p.days} type="button" className={`seg-btn ${days === p.days ? 'active' : ''}`} onClick={() => setDays(p.days)}>
              {p.label}
            </button>
          ))}
        </div>
        {data && <div className="ctt-total"><strong>{data.total.toLocaleString()}</strong> taps</div>}
      </div>

      {loading && !data ? <PageLoading /> : groups.length === 0 ? (
        <EmptyState icon={<TrendingUpIcon size={28} />} title="No taps in this period">
          Taps on partner buttons in live guides show up here.
        </EmptyState>
      ) : (
        <div className="card table-wrap ctt-card">
          <table className="ctt-table">
            <thead>
              <tr>
                <th>Guide</th>
                <th>Where in the guide</th>
                <th>Button</th>
                <th>Opens</th>
                <th className="num">Taps</th>
                <th>Last tap</th>
              </tr>
            </thead>
            <tbody>
              {groups.map((g) => (
                <Fragment key={g.name}>
                  <tr className="ctt-group">
                    <td colSpan={4}>{g.name}</td>
                    <td className="num">{g.total.toLocaleString()}</td>
                    <td />
                  </tr>
                  {g.rows.map((r) => (
                    <tr key={`${r.tour_id}-${r.link_id}`}>
                      <td>
                        <Link to={`/city-tours/edit?id=${r.tour_id}`}>{r.tour_title}</Link>
                        {r.city && <div className="muted">{r.city}</div>}
                      </td>
                      <td>{r.where || '—'}</td>
                      <td>{r.label || <span className="muted">Default text</span>}</td>
                      <td className="ctt-target">
                        {/^https:\/\//.test(r.target)
                          ? <a href={r.target} target="_blank" rel="noreferrer">{r.target}</a>
                          : r.target}
                      </td>
                      <td className="num">{r.taps.toLocaleString()}</td>
                      <td>{formatDate(r.last_tap_at)}</td>
                    </tr>
                  ))}
                </Fragment>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
