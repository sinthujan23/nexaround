import { useEffect, useState } from 'react';
import { Scale } from 'lucide-react';

const API = 'https://api.nexaround.com/api/v1/legal';

const PAGES = {
  experience_customer: {
    badge: 'For travellers',
    intro: 'What you agree to when you request an experience through the NexAround app.',
  },
  experience_provider: {
    badge: 'For experience providers',
    intro: 'What providers agree to before listing experiences on NexAround.',
  },
};

/**
 * The current Experience Booking Terms or Provider Agreement, read live from
 * the API so this page always matches what the app and the partner portal ask
 * people to accept. Edited in the admin panel (Legal & Terms).
 */
export default function ExperienceTerms({ kind }) {
  const [doc, setDoc] = useState(null);
  const [failed, setFailed] = useState(false);
  const page = PAGES[kind];

  useEffect(() => {
    let active = true;
    fetch(`${API}/${kind}`)
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(r.statusText))))
      .then((data) => { if (active) setDoc(data); })
      .catch(() => { if (active) setFailed(true); });
    return () => { active = false; };
  }, [kind]);

  const updated = doc && new Date(doc.updated_at).toLocaleDateString(undefined, {
    day: 'numeric', month: 'long', year: 'numeric',
  });

  return (
    <div style={{ background: '#ffffff', minHeight: '100vh', paddingBottom: '100px' }}>
      <section className="dark-section" style={{ position: 'relative', padding: '160px 24px 70px', textAlign: 'center' }}>
        <div className="container" style={{ position: 'relative' }}>
          <div style={{ maxWidth: '850px', margin: '0 auto' }}>
            <div className="badge badge-teal-glow" style={{ marginBottom: '20px' }}>
              <Scale style={{ width: '14px', height: '14px' }} /> {page.badge}
            </div>
            <h1 style={{ fontSize: 'clamp(2.2rem, 5vw, 3.2rem)', fontWeight: 500, color: '#ffffff', margin: '0 0 16px', lineHeight: 1.15, letterSpacing: '-0.025em' }}>
              {doc?.title || (kind === 'experience_provider' ? 'Experience Provider Agreement' : 'Experience Booking Terms')}
            </h1>
            <p style={{ color: 'rgba(255, 255, 255, 0.85)', fontSize: '1.05rem', lineHeight: 1.7, margin: '0 auto 20px', maxWidth: '680px' }}>
              {page.intro}
            </p>
            {doc && (
              <div style={{ display: 'inline-flex', gap: '8px', fontSize: '0.85rem', color: 'rgba(255,255,255,0.7)', background: 'rgba(255,255,255,0.08)', padding: '6px 16px', borderRadius: 'var(--radius-pill)', border: '1px solid rgba(255,255,255,0.15)' }}>
                <span>Version {doc.version}</span>
                <span>•</span>
                <span>Last updated {updated}</span>
              </div>
            )}
          </div>
        </div>
      </section>

      <section className="container" style={{ maxWidth: '880px', margin: '60px auto 0' }}>
        <div className="feature-card" style={{ padding: 'clamp(28px, 5vw, 56px)' }}>
          {failed && (
            <p style={{ color: 'var(--text-secondary, #5b6b6a)' }}>
              We couldn&apos;t load this document right now. Please try again shortly.
            </p>
          )}
          {!doc && !failed && <p style={{ color: '#8a9796' }}>Loading…</p>}
          {doc?.highlights?.length > 0 && (
            <ul style={{ background: 'rgba(0, 122, 124, 0.07)', borderRadius: '14px', padding: '18px 18px 18px 38px', margin: '0 0 32px', lineHeight: 1.7 }}>
              {doc.highlights.map((line) => <li key={line}>{line}</li>)}
            </ul>
          )}
          {doc && <LegalBody body={doc.body} />}
        </div>
      </section>
    </div>
  );
}

/** "## " heading, "- " bullet, blank line between paragraphs: the same rules as the app. */
function LegalBody({ body }) {
  const blocks = [];
  let paragraph = [];
  const flush = () => {
    if (paragraph.length) blocks.push({ type: 'p', text: paragraph.join(' ') });
    paragraph = [];
  };
  for (const raw of body.split('\n')) {
    const line = raw.trim();
    if (!line) flush();
    else if (line.startsWith('## ')) { flush(); blocks.push({ type: 'h', text: line.slice(3).trim() }); }
    else if (line.startsWith('- ')) {
      flush();
      const last = blocks[blocks.length - 1];
      if (last?.type === 'ul') last.items.push(line.slice(2).trim());
      else blocks.push({ type: 'ul', items: [line.slice(2).trim()] });
    } else paragraph.push(line);
  }
  flush();

  return blocks.map((b, i) => {
    if (b.type === 'h') {
      return <h2 key={i} style={{ fontSize: '1.3rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: i === 0 ? '0 0 12px' : '32px 0 12px' }}>{b.text}</h2>;
    }
    if (b.type === 'ul') {
      return (
        <ul key={i} style={{ paddingLeft: '22px', margin: '0 0 14px', lineHeight: 1.75, color: '#4b5563' }}>
          {b.items.map((t, j) => <li key={j}>{t}</li>)}
        </ul>
      );
    }
    return <p key={i} style={{ lineHeight: 1.75, color: '#4b5563', margin: '0 0 14px' }}>{b.text}</p>;
  });
}
