import { useState, useEffect } from 'react';
import { Smartphone, Sparkles, ShieldCheck, Star, QrCode, CheckCircle2, Zap, ArrowRight } from 'lucide-react';
import StoreButtons from '../components/StoreButtons';

const heroBackgrounds = [
  '/bg_taj_mahal.png',
  '/bg_colosseum_rome.png',
  '/bg_eiffel_tower.png',
  '/bg_sigiriya.png',
  '/bg_pyramids_giza.png',
  '/bg_machu_picchu.png',
  '/bg_great_wall.png',
  '/bg_sydney_opera.png',
  '/bg_statue_liberty.png',
];

export default function GetApp() {
  const [currentBgIndex, setCurrentBgIndex] = useState(0);

  useEffect(() => {
    const timer = setInterval(() => {
      setCurrentBgIndex((prev) => (prev + 1) % heroBackgrounds.length);
    }, 4500);
    return () => clearInterval(timer);
  }, []);
  return (
    <div style={{ background: '#0a1118', minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '140px 24px 80px', position: 'relative', overflow: 'hidden' }}>
      
      {/* Smooth Auto-Rotating Background Images with Cross-Fade */}
      {heroBackgrounds.map((bg, idx) => (
        <div
          key={bg}
          style={{
            position: 'absolute',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundImage: `url(${bg})`,
            backgroundSize: 'cover',
            backgroundPosition: 'center 35%',
            opacity: idx === currentBgIndex ? 0.35 : 0,
            filter: 'brightness(1.1) contrast(1.05)',
            transform: idx === currentBgIndex ? 'scale(1.03)' : 'scale(1)',
            transition: 'opacity 1.4s ease-in-out, transform 5s ease-out',
            zIndex: 1,
            pointerEvents: 'none'
          }}
        />
      ))}
      <div style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, background: 'rgba(8, 10, 20, 0.75)', zIndex: 1, pointerEvents: 'none' }} />
      <div style={{
        position: 'absolute',
        top: '20%',
        left: '50%',
        transform: 'translateX(-50%)',
        width: '800px',
        height: '500px',
        background: 'radial-gradient(ellipse at center, rgba(0, 122, 124, 0.3) 0%, rgba(10, 17, 24, 0) 70%)',
        pointerEvents: 'none',
        zIndex: 2
      }} />

      <div className="container" style={{ position: 'relative', zIndex: 2, maxWidth: '960px' }}>
        
        {/* Main Get App Card (Matching Reference Design) */}
        <div style={{
          padding: '80px 48px',
          textAlign: 'center',
          background: 'linear-gradient(180deg, rgba(240, 249, 255, 0.95) 0%, #ffffff 60%, rgba(234, 247, 247, 0.9) 100%)',
          border: '1px solid rgba(0, 122, 124, 0.25)',
          borderRadius: '32px',
          boxShadow: '0 25px 70px rgba(0, 0, 0, 0.4)',
          margin: '0 auto'
        }}>
          
          {/* Pill Badge */}
          <div style={{ 
            display: 'inline-flex', 
            alignItems: 'center', 
            gap: '8px', 
            background: 'rgba(0, 122, 124, 0.08)', 
            border: '1px solid rgba(0, 122, 124, 0.25)', 
            borderRadius: '9999px', 
            padding: '6px 20px', 
            marginBottom: '24px' 
          }}>
            <span style={{ width: '8px', height: '8px', borderRadius: '50%', background: 'var(--brand-teal)' }} />
            <span style={{ fontSize: '0.82rem', fontWeight: 500, color: 'var(--brand-teal)', letterSpacing: '0.8px', textTransform: 'uppercase' }}>
              GET THE APP
            </span>
          </div>

          {/* Headline */}
          <h1 style={{ 
            fontSize: 'clamp(2.5rem, 5vw, 4.2rem)', 
            fontWeight: 500, 
            color: 'var(--dark-charcoal)', 
            margin: '0 0 18px', 
            lineHeight: 1.12, 
            letterSpacing: '-0.035em' 
          }}>
            One app for everything you need.
          </h1>

          {/* Subtitle */}
          <p style={{ 
            color: 'var(--text-secondary)', 
            margin: '0 auto 40px', 
            fontSize: 'clamp(1.05rem, 2vw, 1.22rem)', 
            maxWidth: '680px', 
            lineHeight: 1.7,
            fontWeight: 400
          }}>
            Download the NexAround app to explore attractions, food, hotels, taxis, and AI itineraries- all in one place, across 50+ global destinations.
          </p>

          {/* Official Black Store Badges */}
          <div style={{ marginBottom: '44px' }}>
            <StoreButtons theme="dark" showRating={false} />
          </div>

          {/* Feature Highlights Row */}
          <div style={{ 
            display: 'flex', 
            justifyContent: 'center', 
            gap: '32px', 
            flexWrap: 'wrap',
            paddingTop: '32px',
            borderTop: '1px solid rgba(0, 122, 124, 0.15)'
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '0.92rem', color: 'var(--dark-charcoal)', fontWeight: 500 }}>
              <ShieldCheck style={{ width: '18px', height: '18px', color: 'var(--brand-teal)' }} />
              <span>100% Free to Download</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '0.92rem', color: 'var(--dark-charcoal)', fontWeight: 500 }}>
              <Zap style={{ width: '18px', height: '18px', color: 'var(--brand-teal)' }} />
              <span>Instant Setup • No Credit Card</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '0.92rem', color: 'var(--dark-charcoal)', fontWeight: 500 }}>
              <CheckCircle2 style={{ width: '18px', height: '18px', color: 'var(--brand-teal)' }} />
              <span>Live Spatial AR Camera</span>
            </div>
          </div>

        </div>

      </div>

    </div>
  );
}
