import { useState } from 'react';
import {
  addDays, addRange, formatDay, isBlocked, monthShape, removeDate, shiftMonth, todayIso,
} from '../availabilityRanges';

const WEEKDAYS = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

const rangeLabel = (r) => (r.start === r.end ? formatDay(r.start) : `${formatDay(r.start)} – ${formatDay(r.end)}`);

/**
 * Month calendar for the days a package cannot be booked.
 *
 * Every day is available unless blocked here. To block: click the first day,
 * then click the last day to block everything between (click the same day
 * again for just that one). Click a blocked day to open it up again.
 * `value` is the list of inclusive ISO ranges the API stores.
 */
export default function AvailabilityCalendar({ value = [], onChange, maxDays = 365 }) {
  const today = todayIso();
  const last = addDays(today, maxDays);
  const firstMonth = today.slice(0, 7);
  const lastMonth = last.slice(0, 7);

  const [month, setMonth] = useState(firstMonth);
  const [pending, setPending] = useState(null);
  const [hover, setHover] = useState(null);

  const { days, startsOn, label } = monthShape(month);
  const ranges = value || [];

  const pick = (day) => {
    if (day < today || day > last) return;
    if (!pending) {
      if (isBlocked(ranges, day)) onChange(removeDate(ranges, day));
      else setPending(day);
      return;
    }
    onChange(addRange(ranges, pending, day));
    setPending(null);
    setHover(null);
  };

  const cancel = () => { setPending(null); setHover(null); };

  const preview = (day) => {
    if (!pending || !hover) return false;
    const lo = pending < hover ? pending : hover;
    const hi = pending < hover ? hover : pending;
    return lo <= day && day <= hi;
  };

  const cells = [];
  for (let i = 0; i < startsOn; i += 1) cells.push(null);
  for (let d = 1; d <= days; d += 1) cells.push(`${month}-${String(d).padStart(2, '0')}`);

  const hint = pending
    ? `Starting ${formatDay(pending)}. Click the last day to block, or click ${formatDay(pending)} again for just that day.`
    : 'Click a day to start blocking. Click a blocked day to make it available again.';

  return (
    <div className="avail" onKeyDown={(e) => { if (e.key === 'Escape' && pending) { e.stopPropagation(); cancel(); } }}>
      <div className="avail-head">
        <button
          type="button" className="avail-nav" aria-label="Previous month"
          disabled={month <= firstMonth} onClick={() => setMonth(shiftMonth(month, -1))}
        >‹</button>
        <div className="avail-month" aria-live="polite">{label}</div>
        <button
          type="button" className="avail-nav" aria-label="Next month"
          disabled={month >= lastMonth} onClick={() => setMonth(shiftMonth(month, 1))}
        >›</button>
      </div>

      <div className="avail-grid" onMouseLeave={() => setHover(null)}>
        {WEEKDAYS.map((w, i) => <div key={`w${i}`} className="avail-dow">{w}</div>)}
        {cells.map((day, i) => {
          if (!day) return <div key={`b${i}`} />;
          const disabled = day < today || day > last;
          const blocked = isBlocked(ranges, day);
          const cls = [
            'avail-day',
            disabled ? 'is-off' : '',
            blocked ? 'is-blocked' : '',
            pending === day ? 'is-pending' : '',
            !blocked && preview(day) ? 'is-preview' : '',
            day === today ? 'is-today' : '',
          ].filter(Boolean).join(' ');
          return (
            <button
              key={day} type="button" className={cls} disabled={disabled}
              aria-label={`${formatDay(day)}, ${blocked ? 'unavailable' : 'available'}`}
              aria-pressed={blocked}
              onClick={() => pick(day)} onMouseEnter={() => setHover(day)}
            >
              {Number(day.slice(8))}
            </button>
          );
        })}
      </div>

      <div className="avail-legend">
        <span><i className="avail-swatch" /> Available</span>
        <span><i className="avail-swatch is-blocked" /> Unavailable</span>
        <span><i className="avail-swatch is-pending" /> Selected</span>
      </div>

      <div className={`avail-hint ${pending ? 'is-active' : ''}`}>
        {hint}
        {pending && <button type="button" className="avail-link" onClick={cancel}>Cancel</button>}
      </div>

      {ranges.length === 0 ? (
        <div className="avail-summary">Available every day.</div>
      ) : (
        <div className="avail-summary">
          <div className="avail-summary-title">
            Unavailable on
            <button type="button" className="avail-link" onClick={() => { cancel(); onChange([]); }}>Clear all</button>
          </div>
          <div className="avail-chips">
            {ranges.map((r, i) => (
              <span key={`${r.start}-${r.end}`} className="avail-chip">
                {rangeLabel(r)}
                <button
                  type="button" aria-label={`Make ${rangeLabel(r)} available`}
                  onClick={() => onChange(ranges.filter((_, j) => j !== i))}
                >×</button>
              </span>
            ))}
          </div>
          <div className="avail-note">Available on every other day.</div>
        </div>
      )}
    </div>
  );
}
