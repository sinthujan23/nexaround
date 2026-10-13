import { useState } from 'react';
import { mediaUrl } from '../api';
import { MapPinIcon } from './Icons';

/** A place's first photo as a small square, or the pin when there is none or it fails to load. */
export default function PlaceThumb({ url, size }) {
  const [failed, setFailed] = useState(false);
  return (
    <div className="xp-avatar" style={size ? { width: size, height: size } : undefined}>
      {url && !failed
        ? <img src={mediaUrl(url)} alt="" loading="lazy" onError={() => setFailed(true)} />
        : <MapPinIcon size={16} />}
    </div>
  );
}
