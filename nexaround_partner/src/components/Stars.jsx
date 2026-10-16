import { StarIcon } from './Icons';

/** Five stars, `value` of them filled. */
export default function Stars({ value, size = 14 }) {
  return (
    <span className="rv-stars" title={`${value} out of 5`} aria-label={`${value} out of 5`}>
      {[1, 2, 3, 4, 5].map((n) => (
        <StarIcon key={n} size={size} className={n <= Math.round(value) ? 'on' : 'off'} />
      ))}
    </span>
  );
}
