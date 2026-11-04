import { Fragment, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { useApi } from '../api';
import { EmptyState, PageError, PageLoading } from '../components/Kit';
import { CreditCardIcon } from '../components/Icons';

const STATUS_LABELS = { confirmed: 'Confirmed', closed: 'Closed' };

const monthLabel = (month) => new Date(`${month}-01T00:00:00`)
  .toLocaleDateString('en-GB', { month: 'short', year: 'numeric' });

const formatDay = (value) => (value
  ? new Date(`${value}T00:00:00`).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })
  : '');

const money = (value, currency) => (value == null
  ? '—'
  : `${currency || ''} ${Number(value).toLocaleString(undefined, { maximumFractionDigits: 2 })}`.trim());

/**
 * NexAround's commission on confirmed bookings: what each traveller pays, what
 * the vendor gets and the difference, as each request copied them when it was
 * sent, by the month of the booked day. Vendors never see this page's figures;
 * their portal shows only their own amounts. The table styles are the City
 * Tours taps report's.
 */
export default function Commission() {
  const [month, setMonth] = useState('');
  const { data, loading, error, refetch } = useApi(
    `/admin/experiences/commission${month ? `?month=${month}` : ''}`
  );

  const groups = useMemo(() => {
    const byVendor = new Map();
    for (const row of data?.rows || []) {
      const key = row.vendor_id || row.vendor_name;
      if (!byVendor.has(key)) byVendor.set(key, { name: row.vendor_name || 'Vendor', rows: [] });
      byVendor.get(key).rows.push(row);
    }
    return [...byVendor.entries()].map(([key, g]) => ({ ...g, key }));
  }, [data]);

  const hourly = (data?.rows || []).some((r) => r.basis === 'per_hour');

  if (error && !data) return <PageError error={error} onRetry={refetch} />;

  return (
    <div>
      <div className="xp-toolbar">
        <div className="seg">
          <button type="button" className={`seg-btn ${month === '' ? 'active' : ''}`} onClick={() => setMonth('')}>
            All time
          </button>
          {(data?.months || []).map((m) => (
            <button key={m} type="button" className={`seg-btn ${month === m ? 'active' : ''}`} onClick={() => setMonth(m)}>
              {monthLabel(m)}
            </button>
          ))}
        </div>
      </div>

      {loading && !data ? <PageLoading /> : groups.length === 0 ? (
        <EmptyState icon={<CreditCardIcon size={28} />} title="No confirmed bookings">
          Bookings a provider has confirmed show here, with NexAround’s commission on each.
        </EmptyState>
      ) : (
        <>
          <div className="card table-wrap ctt-card">
            <table className="ctt-table">
              <thead>
                <tr>
                  <th>Vendor</th>
                  <th className="num">Bookings</th>
                  <th className="num">Travellers pay</th>
                  <th className="num">Vendors get</th>
                  <th className="num">Commission</th>
                </tr>
              </thead>
              <tbody>
                {(data?.totals || []).map((t) => (
                  <tr key={`${t.vendor_id}-${t.currency}`}>
                    <td>{t.vendor_name || 'Vendor'}</td>
                    <td className="num">{t.bookings}</td>
                    <td className="num">{money(t.traveller_amount, t.currency)}</td>
                    <td className="num">{money(t.vendor_amount, t.currency)}</td>
                    <td className="num"><strong>{money(t.commission_amount, t.currency)}</strong></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="card table-wrap ctt-card" style={{ marginTop: 16 }}>
            <table className="ctt-table">
              <thead>
                <tr>
                  <th>Booked day</th>
                  <th>Request</th>
                  <th>Experience</th>
                  <th className="num">Guests</th>
                  <th className="num">Traveller pays</th>
                  <th className="num">Vendor gets</th>
                  <th className="num">Commission</th>
                </tr>
              </thead>
              <tbody>
                {groups.map((g) => (
                  <Fragment key={g.key}>
                    <tr className="ctt-group">
                      <td colSpan={7}>{g.name}</td>
                    </tr>
                    {g.rows.map((r) => {
                      const per = r.basis === 'per_hour' ? ' / hour' : '';
                      return (
                        <tr key={r.id}>
                          <td>{formatDay(r.booked_date)}</td>
                          <td>
                            <Link to={`/enquiries?id=${r.id}`}>{r.reference}</Link>
                            <div className="muted">{STATUS_LABELS[r.status] || r.status}</div>
                          </td>
                          <td>{r.package_title || '—'}</td>
                          <td className="num">{r.party_size ?? '—'}</td>
                          <td className="num">{money(r.traveller_amount, r.currency)}{r.traveller_amount != null && per}</td>
                          <td className="num">{money(r.vendor_amount, r.currency)}{r.vendor_amount != null && per}</td>
                          <td className="num">
                            <strong>{money(r.commission_amount, r.currency)}</strong>{r.commission_amount != null && per}
                            {r.commission_percent != null && <div className="muted">{Number(r.commission_percent)}%</div>}
                          </td>
                        </tr>
                      );
                    })}
                  </Fragment>
                ))}
              </tbody>
            </table>
          </div>
          {hourly && (
            <div className="xp-section-hint" style={{ marginTop: 10 }}>
              Hourly prices count one hour each: requests do not record how many hours were booked.
            </div>
          )}
        </>
      )}
    </div>
  );
}
