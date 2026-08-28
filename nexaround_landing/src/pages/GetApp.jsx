import { Smartphone, Sparkles, ShieldCheck, Star, QrCode, CheckCircle2, Zap, ArrowRight } from 'lucide-react';
import StoreButtons from '../components/StoreButtons';

export default function GetApp() {
  return (
    <div style={{ background: '#ffffff', minHeight: '85vh', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '120px 24px 80px', position: 'relative', overflow: 'hidden' }}>
      
      {/* Ambient background glow */}
      <div style={{
        position: 'absolute',
        top: '15%',
        left: '50%',
        transform: 'translateX(-50%)',
        width: '800px',
        height: '500px',
        background: 'radial-gradient(ellipse at center, rgba(0, 122, 124, 0.12) 0%, rgba(255, 255, 255, 0) 70%)',
        pointerEvents: 'none',
        zIndex: 1
      }} />

      <div className="container" style={{ position: 'relative', zIndex: 2, maxWidth: '960px' }}>
        
        {/* Main Get App Card (Matching Reference Design) */}
        <div style={{
          padding: '80px 48px',
          textAlign: 'center',
          background: 'linear-gradient(180deg, rgba(240, 249, 255, 0.7) 0%, #ffffff 60%, rgba(234, 247, 247, 0.6) 100%)',
          border: '1px solid rgba(0, 122, 124, 0.25)',
          borderRadius: '32px',
          boxShadow: '0 25px 70px -15px rgba(0, 122, 124, 0.12)',
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
            <span style={{ fontSize: '0.82rem', fontWeight: 800, color: 'var(--brand-teal)', letterSpacing: '0.8px', textTransform: 'uppercase' }}>
              GET THE APP
            </span>
          </div>

          {/* Headline */}
          <h1 style={{ 
            fontSize: 'clamp(2.5rem, 5vw, 4.2rem)', 
            fontWeight: 900, 
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
            Download the NexAround app to explore attractions, food, hotels, taxis, and AI itineraries — all in one place, across 50+ global destinations.
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
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '0.92rem', color: 'var(--dark-charcoal)', fontWeight: 600 }}>
              <ShieldCheck style={{ width: '18px', height: '18px', color: 'var(--brand-teal)' }} />
              <span>100% Free to Download</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '0.92rem', color: 'var(--dark-charcoal)', fontWeight: 600 }}>
              <Zap style={{ width: '18px', height: '18px', color: 'var(--brand-teal)' }} />
              <span>Instant Setup • No Credit Card</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '0.92rem', color: 'var(--dark-charcoal)', fontWeight: 600 }}>
              <CheckCircle2 style={{ width: '18px', height: '18px', color: 'var(--brand-teal)' }} />
              <span>Live Spatial AR Camera</span>
            </div>
          </div>

        </div>

      </div>

    </div>
  );
}
