import { NavLink } from 'react-router-dom';

/** Tabs that are pages: each is a URL, so Back and refresh keep the place. */
export default function TabNav({ items, className = '' }) {
  return (
    <div className={`xp-tabs ${className}`}>
      {items.map(({ to, label, end }) => (
        <NavLink key={to} to={to} end={end} className={({ isActive }) => `xp-tab ${isActive ? 'active' : ''}`}>
          {label}
        </NavLink>
      ))}
    </div>
  );
}
