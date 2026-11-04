import { useState } from 'react';
import { useApi } from '../api';
import { CompassIcon } from './Icons';
import { Loading, EmptyState } from './Kit';
import { countryFlag, countryName } from '../constants/countries';

const SHOWN = 8;

/**
 * Explorers per country they use the app from, for the Users page. The
 * country is the one their latest request to the API came from (IP address),
 * so a traveller abroad counts where they are, not where they are from.
 */
export default function ExplorerCountries() {
  const { data, loading, error } = useApi('/admin/users/countries');
  const [showAll, setShowAll] = useState(false);

  let body;
  if (!data) {
    body = loading
      ? <Loading>Loading countries…</Loading>
      : <EmptyState>Could not load countries: {error}</EmptyState>;
  } else if (data.countries.length === 0) {
    body = <EmptyState>Countries appear once the IP country list has loaded.</EmptyState>;
  } else {
    const top = data.countries[0].explorers;
    const shown = showAll ? data.countries : data.countries.slice(0, SHOWN);
    const hidden = data.countries.slice(SHOWN);
    const unknown = data.total - data.located;

    body = (
      <>
        <ol className="countries-grid">
          {shown.map((c) => (
            <li key={c.country_code}>
              <div className="countries-row">
                <span className="countries-name">
                  {countryFlag(c.country_code)} {countryName(c.country_code)}
                </span>
                <span className="countries-count">
                  {c.explorers.toLocaleString()}
                  <small>{Math.round((c.explorers / data.located) * 100)}%</small>
                </span>
              </div>
              <div className="activity-meter">
                <div style={{ width: `${(c.explorers / top) * 100}%` }} />
              </div>
            </li>
          ))}
        </ol>
        <div className="countries-foot">
          {hidden.length > 0 && (
            <button type="button" className="activity-more" onClick={() => setShowAll((v) => !v)}>
              {showAll
                ? 'Show fewer'
                : `Show ${hidden.length} more ${hidden.length === 1 ? 'country' : 'countries'}`}
            </button>
          )}
          {unknown > 0 && (
            <span title="They have not used the app since IP addresses started being recorded (25 May 2026)">
              {unknown.toLocaleString()} not located
            </span>
          )}
          <span>
            IP data by <a href="https://db-ip.com" target="_blank" rel="noreferrer">DB-IP</a>
          </span>
        </div>
      </>
    );
  }

  return (
    <section className="card activity-card" aria-labelledby="explorer-countries-title">
      <div className="activity-head">
        <div>
          <h2 id="explorer-countries-title">
            <CompassIcon size={18} style={{ color: 'var(--accent)' }} />
            Where explorers are
          </h2>
          <p>
            Country of each explorer's latest connection
            {data && data.countries.length > 0 && (
              <> · {data.countries.length} {data.countries.length === 1 ? 'country' : 'countries'},{' '}
                {data.located.toLocaleString()} of {data.total.toLocaleString()} explorers located</>
            )}
          </p>
        </div>
      </div>
      {body}
    </section>
  );
}
