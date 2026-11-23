import { useState } from 'react';
import { mediaUrl } from '../api';
import PhoneFrame, { AppMarkdown, MIcon, StatusBar } from './PhoneFrame';

// A TravelByte as the app draws it (nexaround_app/lib/features/
// travel_stories): the card first in Home's Travel Stories row
// (travel_story_card.dart), the full-screen viewer (travel_stories_page.dart)
// and the "Read the experience" long read (story_experience_page.dart).

const OFFICIAL_NAME = 'TravelByte';
const LOGO = '/static/brand/nexaround_mark.png';
// _getCategoryColor: a place label ("CHINA · FURONG TOWN") falls to teal.
const LABEL_COLOR = '#009688';

const SCREENS = [['card', 'Home card'], ['viewer', 'Story'], ['read', 'Read the experience']];

function Avatar({ size }) {
  return (
    <span className="tbp-avatar" style={{ width: size, height: size, padding: size * 0.11 }}>
      <img src={mediaUrl(LOGO)} alt="" />
    </span>
  );
}

function Name({ size, color = '#000' }) {
  return (
    <span className="tbp-name" style={{ fontSize: size, color }}>
      {OFFICIAL_NAME} <MIcon name="verified" size={size + 2} color="#1D9BF0" />
    </span>
  );
}

/** ReadExperienceTab: the green pill that opens the long read. */
function ReadTab({ label = 'Read the experience', compact = false }) {
  const size = compact ? 10.5 : 13;
  return (
    <span className={`tbp-tab ${compact ? 'compact' : ''}`} style={{ fontSize: size }}>
      <MIcon name="auto_stories" size={size + 3} /> {label} <MIcon name="arrow_forward" size={size + 2} />
    </span>
  );
}

/** The card's photo block: one, two side by side, or one big and two stacked with "+N". */
function PhotoGrid({ urls }) {
  const shown = urls.slice(0, 3);
  if (!shown.length) return <div className="tbp-grid-empty">Photos show here</div>;
  const img = (u) => <img src={mediaUrl(u)} alt="" />;
  if (shown.length === 1) return <div className="tbp-grid">{img(shown[0])}</div>;
  if (shown.length === 2) {
    return <div className="tbp-grid two"><div>{img(shown[0])}</div><div>{img(shown[1])}</div></div>;
  }
  return (
    <div className="tbp-grid three">
      <div className="big">{img(shown[0])}</div>
      <div className="col">
        <div>{img(shown[1])}</div>
        <div>
          {img(shown[2])}
          {urls.length > 3 && <span className="tbp-more">+{urls.length - 3}</span>}
        </div>
      </div>
    </div>
  );
}

function HomeCard({ story, label, hasArticle }) {
  const urls = story.image_urls || [];
  return (
    <div className="tbp-home">
      <StatusBar />
      <div className="tbp-section">Travel Stories</div>
      <div className="tbp-row">
        <div className="tbp-card">
          <div className="tbp-card-head">
            <Avatar size={32} />
            <span className="tbp-card-who">
              <Name size={12} />
              <span className="tbp-time">Just now</span>
            </span>
            {label && (
              <span className="tbp-label" style={{ color: LABEL_COLOR, background: `${LABEL_COLOR}14`, borderColor: `${LABEL_COLOR}4d` }}>
                {label}
              </span>
            )}
          </div>
          <div className="tbp-photo">
            <PhotoGrid urls={urls} />
            {story.location_name && (
              <span className="tbp-place"><MIcon name="location_on" size={10} /> <span>{story.location_name}</span></span>
            )}
            {urls.length > 1 && <span className="tbp-layers"><MIcon name="layers" size={14} /></span>}
          </div>
          <div className={`tbp-intro ${hasArticle ? 'two' : 'three'}`}>{story.description || 'The short intro shows here.'}</div>
          <div className="tbp-foot">
            <span><MIcon name="favorite_border" size={16} /> {story.likes ?? 0}</span>
            <span><MIcon name="chat_bubble_outline" size={16} /> {story.comments ?? 0}</span>
            {hasArticle && <span className="tbp-foot-tab"><ReadTab label="See more" compact /></span>}
          </div>
        </div>
        <div className="tbp-card tbp-card-next" />
      </div>
    </div>
  );
}

function Viewer({ story, label, hasArticle }) {
  const urls = story.image_urls || [];
  const [index, setIndex] = useState(0);
  const at = Math.min(index, Math.max(urls.length - 1, 0));
  const photo = urls[at];
  return (
    <div className="tbp-viewer">
      {photo && <div className="tbp-viewer-bg" style={{ backgroundImage: `url("${mediaUrl(photo)}")` }} />}
      <div className="tbp-viewer-shade" />
      <div className="tbp-viewer-body">
        <StatusBar light />
        <div className="tbp-bars">
          {(urls.length ? urls : ['']).map((u, i) => <span key={i} className={i <= at ? 'on' : ''} />)}
        </div>
        <div className="tbp-viewer-head">
          <Avatar size={36} />
          <span className="tbp-viewer-who">
            <Name size={13} color="#fff" />
            <span>{story.description}</span>
          </span>
          <MIcon name="close" size={28} color="#fff" />
        </div>
        <div className="tbp-viewer-photo">
          {photo ? <img src={mediaUrl(photo)} alt="" /> : <span>Photos show here</span>}
          {urls.length > 1 && (
            <>
              <button type="button" className="tbp-tap left" aria-label="Previous photo" onClick={() => setIndex(Math.max(at - 1, 0))} />
              <button type="button" className="tbp-tap right" aria-label="Next photo" onClick={() => setIndex(Math.min(at + 1, urls.length - 1))} />
            </>
          )}
        </div>
        <div className="tbp-viewer-text">
          <div className="tbp-viewer-tags">
            {story.location_name && (
              <span className="tbp-viewer-place">
                <MIcon name="location_on" size={13} color="#FF5252" /> <span>{story.location_name}</span>
                <MIcon name="arrow_forward_ios" size={8} color="rgba(255,255,255,0.54)" />
              </span>
            )}
            {label && <span className="tbp-viewer-label" style={{ color: LABEL_COLOR }}>{label}</span>}
          </div>
          <div className="tbp-viewer-desc">{story.description || 'The short intro shows here.'}</div>
          {hasArticle && <div style={{ marginTop: 12 }}><ReadTab /></div>}
          <div className="tbp-viewer-social">
            <span><MIcon name="favorite_border" size={22} color="#fff" /> {story.likes ?? 0}</span>
            <span><MIcon name="chat_bubble_outline" size={20} color="#fff" /> {story.comments ?? 0} Comments</span>
          </div>
        </div>
      </div>
    </div>
  );
}

function LongRead({ story, label }) {
  const urls = story.image_urls || [];
  const [index, setIndex] = useState(0);
  const at = Math.min(index, Math.max(urls.length - 1, 0));
  const heading = story.title?.trim() || story.location_name;
  return (
    <div className="tbp-read">
      <div className="tbp-read-hero">
        {urls[at] ? <img src={mediaUrl(urls[at])} alt="" /> : <span className="tbp-read-hero-empty" />}
        <div className="tbp-read-top"><StatusBar /></div>
        <span className="tbp-read-back"><MIcon name="arrow_back" size={20} /></span>
        {urls.length > 1 && (
          <span className="tbp-dots">
            {urls.map((u, i) => (
              <button key={i} type="button" className={i === at ? 'on' : ''} onClick={() => setIndex(i)} aria-label={`Photo ${i + 1}`} />
            ))}
          </span>
        )}
      </div>
      <div className="tbp-read-body">
        <div className="tbp-read-by">
          <Avatar size={32} />
          <Name size={13} />
          {label && <span className="tbp-read-label">{label}</span>}
        </div>
        {story.title?.trim() && <div className="tbp-read-title">{story.title.trim()}</div>}
        <div className="tbp-read-place"><MIcon name="location_on" size={15} color="#007A7C" /> {story.location_name || heading}</div>
        <div className="tbp-read-intro">{story.description}</div>
        <AppMarkdown text={story.article_md} />
      </div>
    </div>
  );
}

/**
 * A phone showing the TravelByte being written, on the three screens the app
 * shows it on. `story` is the form as it is now; `label` the app's place label.
 */
export default function TravelBytePreview({ story, label }) {
  const [screen, setScreen] = useState('card');
  const hasArticle = Boolean((story.article_md || '').trim());
  const shown = !hasArticle && screen === 'read' ? 'card' : screen;
  return (
    <PhoneFrame
      tabs={hasArticle ? SCREENS : SCREENS.slice(0, 2)}
      tab={shown}
      onTab={setScreen}
      dark={shown === 'viewer'}
      note={shown === 'viewer' ? 'As in the app. Tap the photo’s sides to move between photos.' : 'As in the app.'}
    >
      {shown === 'card' && <HomeCard story={story} label={label} hasArticle={hasArticle} />}
      {shown === 'viewer' && <Viewer story={story} label={label} hasArticle={hasArticle} />}
      {shown === 'read' && <LongRead story={story} label={label} />}
    </PhoneFrame>
  );
}
