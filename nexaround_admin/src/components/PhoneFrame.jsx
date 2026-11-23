import { Fragment, useEffect, useRef, useState } from 'react';
import { inlineRuns, parseBlocks } from '../descriptionFormat';

// The iPhone frame the City Guides and Museums previews draw (.ctp-* styles),
// shared by the TravelByte and Experience previews: a 402 x 874 screen in a
// 10px frame, shrunk as a whole to fit its column, the window and, inside a
// scrolling panel, that panel's height.
const PHONE_W = 402;
const PHONE_H = 874;
const FRAME = 10;
const OUTER_W = PHONE_W + FRAME * 2;
const OUTER_H = PHONE_H + FRAME * 2;

/** A Material icon, as the app's Icons.*_rounded draw. */
export const MIcon = ({ name, size, color, style }) => (
  <span className="material-icons-round" style={{ fontSize: size, color, ...style }} aria-hidden="true">{name}</span>
);

export function StatusBar({ light = false }) {
  return (
    <div className={`ctp-status ${light ? 'light' : ''}`}>
      <span>9:41</span>
      <span className="ctp-status-icons">
        <MIcon name="signal_cellular_alt" size={17} />
        <MIcon name="wifi" size={17} />
        <MIcon name="battery_full" size={17} style={{ transform: 'rotate(90deg)' }} />
      </span>
    </div>
  );
}

function Inline({ text }) {
  return inlineRuns(text).map((run, i) => {
    if (run.kind === 'bold') return <strong key={i}>{run.text}</strong>;
    if (run.kind === 'italic') return <em key={i}>{run.text}</em>;
    return <Fragment key={i}>{run.text}</Fragment>;
  });
}

/** ExperienceDescription (flutter_markdown with the app's style sheet). Built from elements, never raw HTML. */
export function AppMarkdown({ text }) {
  const blocks = parseBlocks(text || '');
  return (
    <div className="ctp-md">
      {blocks.map((b, i) => {
        if (b.type === 'heading') return <div key={i} className={`ctp-md-h${b.level}`}><Inline text={b.text} /></div>;
        if (b.type === 'divider') return <div key={i} className="ctp-md-hr" />;
        if (b.type === 'ul' || b.type === 'ol') {
          return (
            <div key={i} className="ctp-md-list">
              {b.items.map((t, j) => (
                <div key={j} className="ctp-md-li">
                  <span className="ctp-md-bullet">{b.type === 'ul' ? '•' : `${j + 1}.`}</span>
                  <span><Inline text={t} /></span>
                </div>
              ))}
            </div>
          );
        }
        return (
          <p key={i}>
            {b.lines.map((l, j) => <Fragment key={j}>{j > 0 && <br />}<Inline text={l} /></Fragment>)}
          </p>
        );
      })}
    </div>
  );
}

function useFitScale(root, fit) {
  const [scale, setScale] = useState(1);
  useEffect(() => {
    const measure = () => {
      if (!root.current || !fit.current) return;
      const box = root.current.getBoundingClientRect();
      const phone = fit.current.getBoundingClientRect();
      const around = (phone.top - box.top) + (box.bottom - phone.bottom);
      const header = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--header-h')) || 0;
      let roomH = window.innerHeight - header - 32 - around;
      // Inside a scrolling panel (a page pane or a drawer) the phone stays
      // in view as the form scrolls, so it must fit that panel's height.
      const panel = root.current.closest('.xp-body, .drawer-body');
      if (panel) roomH = Math.min(roomH, panel.clientHeight - around - 24);
      setScale(Math.max(0.4, Math.min(1, root.current.clientWidth / OUTER_W, roomH / OUTER_H)));
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(root.current);
    window.addEventListener('resize', measure);
    return () => {
      observer.disconnect();
      window.removeEventListener('resize', measure);
    };
  }, [root, fit]);
  return scale;
}

/**
 * The phone, with a row of tabs above it to pick which screen it shows
 * (`tabs`: [key, label] pairs) and a line under it.
 */
export default function PhoneFrame({ tabs = [], tab, onTab, note = 'As in the app.', dark = false, children }) {
  const root = useRef(null);
  const fit = useRef(null);
  const scale = useFitScale(root, fit);
  return (
    <div className="ctp" ref={root}>
      {tabs.length > 1 && (
        <div className="ctp-tabs">
          <div className="seg">
            {tabs.map(([key, label]) => (
              <button key={key} type="button" className={`seg-btn ${tab === key ? 'active' : ''}`} onClick={() => onTab(key)}>
                {label}
              </button>
            ))}
          </div>
        </div>
      )}
      <div className="ctp-fit" ref={fit} style={{ width: OUTER_W * scale, height: OUTER_H * scale }}>
        <div className="ctp-phone" style={{ transform: `scale(${scale})` }}>
          <div className="ctp-screen" style={dark ? { background: '#000' } : undefined}>
            <div className="ctp-page">{children}</div>
          </div>
          <span className="ctp-island" />
        </div>
      </div>
      {note && <div className="ctp-note">{note}</div>}
    </div>
  );
}
