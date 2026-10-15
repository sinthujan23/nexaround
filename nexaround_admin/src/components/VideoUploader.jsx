import { useEffect, useRef, useState } from 'react';
import { apiUploadFile, mediaUrl } from '../api';
import { TrashIcon } from './Icons';

// Mirror the server (app/services/experience_upload.py), so a file that would
// be refused is refused here at once instead of after a long upload.
const ALLOWED = ['.mp4', '.mov', '.webm'];
const MAX_MB = 45;

/**
 * Video gallery editor for a package: upload with progress, preview, remove.
 *
 * Sent one file per request. The server caps a request body at 50 MB and the
 * panel shows progress per file. Photos use ImageUploader; this is separate
 * because a video needs progress and a player, not a thumbnail.
 */
export default function VideoUploader({
  value = [],
  onChange,
  label = 'Videos',
  max = 3,
  uploadEndpoint = '/admin/experiences/upload-video',
  // Same contract as ImageUploader: true while uploading, false when done or
  // when this component goes away. The owning form must not save in between.
  onUploadingChange,
}) {
  const inputRef = useRef(null);
  const [uploading, setUploading] = useState(false);
  const [progress, setProgress] = useState({ index: 0, total: 0, pct: 0 });
  const [errors, setErrors] = useState([]);

  const urls = value || [];
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
      // Leaving mid-upload: the result must not be written into whatever
      // record is open next.
      mountedRef.current = false;
      notifyRef.current?.(false);
    };
  }, []);

  const handleFiles = async (e) => {
    const picked = Array.from(e.target.files || []);
    if (inputRef.current) inputRef.current.value = '';
    if (picked.length === 0) return;

    const problems = [];
    const room = Math.max(max - urls.length, 0);
    const accepted = [];
    picked.forEach((file) => {
      const ext = `.${(file.name.split('.').pop() || '').toLowerCase()}`;
      if (!ALLOWED.includes(ext)) problems.push(`${file.name}: only MP4, MOV or WebM videos are allowed.`);
      else if (file.size > MAX_MB * 1024 * 1024) problems.push(`${file.name}: larger than ${MAX_MB} MB.`);
      else if (accepted.length >= room) problems.push(`${file.name}: a package can have at most ${max} videos.`);
      else accepted.push(file);
    });
    setErrors(problems);
    if (accepted.length === 0) return;

    setUploading(true);
    let current = urlsRef.current;
    try {
      for (let i = 0; i < accepted.length; i += 1) {
        if (!mountedRef.current) return;
        setProgress({ index: i + 1, total: accepted.length, pct: 0 });
        try {
          const res = await apiUploadFile(uploadEndpoint, accepted[i], {
            onProgress: (f) => {
              if (mountedRef.current) setProgress({ index: i + 1, total: accepted.length, pct: Math.round(f * 100) });
            },
          });
          if (!mountedRef.current) return;
          current = [...current, ...(res.urls || [])];
          onChange(current);
        } catch (err) {
          if (!mountedRef.current) return;
          problems.push(`${accepted[i].name}: ${err.message || 'Upload failed.'}`);
          setErrors([...problems]);
          // A network failure will fail the rest too; anything else is per file.
          if (err.isNetwork) break;
        }
      }
    } finally {
      if (mountedRef.current) setUploading(false);
    }
  };

  const remove = (index) => onChange(urls.filter((_, i) => i !== index));

  return (
    <div className="form-group">
      <label className="form-label">{label}</label>

      {urls.length > 0 && (
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '10px', marginBottom: '12px' }}>
          {urls.map((url, index) => (
            <div
              key={`${url}-${index}`}
              style={{
                position: 'relative', width: '200px', height: '120px', borderRadius: '10px',
                overflow: 'hidden', border: '1px solid var(--border)', background: '#000',
              }}
            >
              <video
                src={mediaUrl(url)} controls preload="metadata" playsInline
                style={{ width: '100%', height: '100%', objectFit: 'contain' }}
              />
              <button
                type="button" className="action-icon-btn" title="Remove video"
                onClick={() => remove(index)} disabled={uploading}
                style={{ position: 'absolute', top: '4px', right: '4px', width: '22px', height: '22px' }}
              >
                <TrashIcon size={12} />
              </button>
            </div>
          ))}
        </div>
      )}

      <input
        ref={inputRef}
        type="file"
        accept=".mp4,.mov,.webm,video/mp4,video/quicktime,video/webm"
        multiple
        className="form-input"
        onChange={handleFiles}
        disabled={uploading || urls.length >= max}
      />
      <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '6px' }}>
        {urls.length >= max
          ? `Limit reached: ${max} videos. Remove one to add another.`
          : `MP4, MOV or WebM, up to ${MAX_MB} MB each, up to ${max} videos.`}
      </div>

      {uploading && (
        <div
          role="status"
          style={{
            fontSize: '13px', fontWeight: 600, marginTop: '8px', padding: '8px 12px',
            borderRadius: '8px', background: 'var(--surface-2, #fef3c7)', color: '#92400e',
            border: '1px solid #fcd34d',
          }}
        >
          Uploading video {progress.index} of {progress.total}… {progress.pct}% — wait until this finishes before saving.
          <div style={{ height: 6, borderRadius: 3, background: '#fde68a', marginTop: 6, overflow: 'hidden' }}>
            <div style={{ height: '100%', width: `${progress.pct}%`, background: '#d97706', transition: 'width .2s' }} />
          </div>
        </div>
      )}
      {errors.map((msg) => (
        <div key={msg} style={{ fontSize: '12px', color: 'var(--danger)', marginTop: '6px' }}>{msg}</div>
      ))}
    </div>
  );
}
