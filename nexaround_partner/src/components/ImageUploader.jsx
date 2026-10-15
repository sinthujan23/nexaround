import { useEffect, useRef, useState } from 'react';
import { apiUpload, mediaUrl } from '../api';
import { ImageIcon, TrashIcon } from './Icons';

/**
 * Multi-image gallery editor.
 *
 * Deliberately NOT the pattern used by Attractions.jsx, which reads the file
 * with FileReader.readAsDataURL and stores a base64 data URI in photo_urls[].
 * For a vendor gallery that would bloat every database row, every API response
 * and every app payload with megabytes of inlined image. These upload to
 * /admin/experiences/upload and store the returned /static/... paths.
 */
export default function ImageUploader({
  value = [],
  onChange,
  label = 'Images',
  // Defaulted to the admin endpoint so every existing call site is unchanged.
  // The partner portal passes its own, which is scoped to one vendor and
  // quota'd; without the prop the two copies would drift and the partner one
  // — the half reachable by a third party — would be the one left behind.
  uploadEndpoint = '/admin/experiences/upload',
  // Called with true while a batch is uploading and false when it is done or
  // this component goes away. The form that owns it must not save in between:
  // the new URLs only reach `value` when the upload finishes, so a save made
  // before then silently leaves the photos out.
  onUploadingChange,
}) {
  const inputRef = useRef(null);
  const [uploading, setUploading] = useState(false);
  const [count, setCount] = useState(0);
  const [error, setError] = useState('');

  const urls = value || [];

  // The upload outlives the render that started it, so it reads the gallery
  // as it is when the upload ends, not as it was when it began.
  const urlsRef = useRef(urls);
  const notifyRef = useRef(onUploadingChange);
  const mountedRef = useRef(true);
  useEffect(() => {
    urlsRef.current = urls;
    notifyRef.current = onUploadingChange;
  });

  useEffect(() => { notifyRef.current?.(uploading); }, [uploading]);
  useEffect(() => {
    mountedRef.current = true;
    return () => {
      // Leaving mid-upload: the owner is no longer waiting on us, and the
      // result must not be written into whatever record is open next.
      mountedRef.current = false;
      notifyRef.current?.(false);
    };
  }, []);

  const handleFiles = async (e) => {
    const files = e.target.files;
    if (!files || files.length === 0) return;

    setUploading(true);
    setCount(files.length);
    setError('');
    try {
      const res = await apiUpload(uploadEndpoint, files);
      if (mountedRef.current) onChange([...urlsRef.current, ...(res.urls || [])]);
    } catch (err) {
      if (mountedRef.current) setError(err.message || 'Upload failed.');
    } finally {
      if (mountedRef.current) {
        setUploading(false);
        // Reset, or picking the same file twice in a row fires no change event.
        if (inputRef.current) inputRef.current.value = '';
      }
    }
  };

  const move = (index, delta) => {
    const target = index + delta;
    if (target < 0 || target >= urls.length) return;
    const next = [...urls];
    [next[index], next[target]] = [next[target], next[index]];
    onChange(next);
  };

  const remove = (index) => {
    onChange(urls.filter((_, i) => i !== index));
  };

  return (
    <div className="form-group">
      {/* Optional: inside a titled Section the section heading does this job. */}
      {label && <label className="form-label">{label}</label>}

      {urls.length > 0 && (
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '10px', marginBottom: '12px' }}>
          {urls.map((url, index) => (
            <div
              key={`${url}-${index}`}
              style={{
                position: 'relative', width: '96px', height: '96px',
                borderRadius: '10px', overflow: 'hidden',
                border: '1px solid var(--border)',
                backgroundImage: `url(${mediaUrl(url)})`,
                backgroundSize: 'cover', backgroundPosition: 'center',
              }}
            >
              {index === 0 && (
                <span
                  className="badge badge-green"
                  style={{ position: 'absolute', top: '4px', left: '4px' }}
                >
                  Cover
                </span>
              )}
              <div style={{ position: 'absolute', bottom: '4px', left: '4px', display: 'flex', gap: '4px' }}>
                <button
                  type="button" className="action-icon-btn" title="Move left"
                  onClick={() => move(index, -1)} disabled={index === 0}
                  style={{ width: '22px', height: '22px', fontSize: '11px' }}
                >←</button>
                <button
                  type="button" className="action-icon-btn" title="Move right"
                  onClick={() => move(index, 1)} disabled={index === urls.length - 1}
                  style={{ width: '22px', height: '22px', fontSize: '11px' }}
                >→</button>
              </div>
              <button
                type="button" className="action-icon-btn" title="Remove"
                onClick={() => remove(index)}
                style={{ position: 'absolute', top: '4px', right: '4px', width: '22px', height: '22px' }}
              >
                <TrashIcon size={12} />
              </button>
            </div>
          ))}
        </div>
      )}

      {urls.length === 0 && (
        <div
          className="empty-state"
          style={{ padding: '18px', marginBottom: '12px', border: '1px dashed var(--border)', borderRadius: '10px' }}
        >
          <ImageIcon size={24} />
          <div style={{ fontSize: '13px', marginTop: '6px' }}>
            No images yet. The first image becomes the card photo.
          </div>
        </div>
      )}

      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        multiple
        className="form-input"
        onChange={handleFiles}
        disabled={uploading}
      />
      {uploading && (
        <div
          role="status"
          style={{
            fontSize: '13px', fontWeight: 600, marginTop: '8px', padding: '8px 12px',
            borderRadius: '8px', background: 'var(--surface-2, #fef3c7)', color: '#92400e',
            border: '1px solid #fcd34d',
          }}
        >
          Uploading {count} photo{count === 1 ? '' : 's'}… wait until this finishes before saving.
        </div>
      )}
      {error && (
        <div style={{ fontSize: '12px', color: 'var(--danger)', marginTop: '6px' }}>{error}</div>
      )}
    </div>
  );
}
