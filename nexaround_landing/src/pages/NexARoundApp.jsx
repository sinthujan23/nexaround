import { useState } from 'react';
import { NavLink } from 'react-router-dom';
import { 
  Sparkles, Camera, MapPin, Compass, BookOpen, 
  MessageSquare, Layers, Download, CheckCircle2, 
  ArrowRight, Smartphone, ShieldCheck, Zap, Globe,
  Landmark, Cpu, Award, Volume2, Clock, Eye, Play, Star,
  ChevronDown, ChevronUp
} from 'lucide-react';
import StoreButtons from '../components/StoreButtons';

export default function NexARoundApp() {
  const [expandedStory, setExpandedStory] = useState(false);

  const appFeatures = [
    {
      id: 'ar',
      num: '01',
      badge: 'Spatial Augmented Reality',
      title: 'AR Location & Landmark Discovery',
      subtitle: 'Real-Time Camera Recognition for Landmarks & Art',
      desc: 'Simply raise your phone and spin it around. NexAround overlays nearby attractions, restaurants, historic monuments, and transport hubs directly onto your real-world camera view with instant orientation.',
      icon: <Camera style={{ width: '26px', height: '26px', color: '#007A7C' }} />,
      image: '/app_scan_landmark_v4.png',
      highlights: [
        'Sub-500ms visual landmark identification',
        'Interactive 3D spatial architectural cutaways',
        'Spatial vantage point landmark storytelling',
        'Works with monuments, ruins & museum paintings'
      ]
    },
    {
      id: 'neva',
      num: '02',
      badge: 'Conversational Concierge',
      title: 'Neva AI Travel Companion',
      subtitle: 'Hyper-Local Wisdom Right in Your Pocket',
      desc: 'Neva is your personal 24/7 travel guide: always with you, never overbearing. Ask her about what you see, where to eat, or how to get there. She understands your location, camera view, and preferences.',
      icon: <MessageSquare style={{ width: '26px', height: '26px', color: '#007A7C' }} />,
      image: '/meet_neva_v4.png',
      highlights: [
        'Natural conversational voice & text intelligence',
        'Authentic culinary & hidden gem recommendations',
        'Emergency numbers, embassy contacts & safety guidance',
        'Dynamic live itinerary modifications'
      ]
    },
    {
      id: 'stories',
      num: '03',
      badge: 'Explorer Community',
      title: 'Travel Stories & Visual Feeds',
      subtitle: 'Authentic Visual Logs from Fellow Travelers',
      desc: 'Discover authentic visual travel stories, photo logs, and curated itineraries shared by verified explorers who have walked the path before you across Europe, Asia, and the Americas.',
      icon: <Globe style={{ width: '26px', height: '26px', color: '#007A7C' }} />,
      image: '/app_travel_stories_v4.png',
      highlights: [
        'Visual photo diaries & verified traveler notes',
        'Real user tips on tickets, lines & hidden angles',
        'Interactive route sharing & itinerary clones'
      ]
    },
    {
      id: 'odyssey',
      num: '04',
      badge: 'Smart Trip Engine',
      title: 'Odyssey AI Travel Planner',
      subtitle: 'Multi-Day Optimized Itineraries in Seconds',
      desc: 'Tell Odyssey your destination, travel dates, interests, and budget: and it crafts a full multi-day itinerary with time-optimized routes, verified opening hours, and real-time updates.',
      icon: <Compass style={{ width: '26px', height: '26px', color: '#007A7C' }} />,
      image: '/app_cap_04_v4.png',
      highlights: [
        'Dynamic multi-day route & schedule optimization',
        'Budget-aware planning (Hostels to 5-Star Luxury)',
        'Live opening hours & crowd density consideration',
        'One-tap sync to Apple Maps & Google Maps'
      ]
    },
    {
      id: 'journal',
      num: '05',
      badge: 'Digital Passport Log',
      title: 'Travel Journal & Memory Archive',
      subtitle: 'Automatic Memory Archive & Landmark Stamps',
      desc: 'Your journey, documented automatically. Captures the places you visit, landmark stamps, notes, and photos to create a personal searchable travel memoir.',
      icon: <BookOpen style={{ width: '26px', height: '26px', color: '#007A7C' }} />,
      image: '/new_journal_entry.png',
      highlights: [
        'Automatic GPS landmark passport stamps & achievements',
        'Private photo journal & travel logbook archive',
        'Country counters & personal travel statistics'
      ]
    },
    {
      id: 'museum',
      num: '06',
      badge: 'Cultural Heritage',
      title: 'Curated Museum & Heritage Guides',
      subtitle: 'Expert Exhibit Walkthroughs & Gallery Floorplans',
      desc: 'Transform complex museum layouts and ancient ruins into intuitive personal tours. Access step-by-step exhibit walkthroughs, must-see masterworks, and integrated ticket booking.',
      icon: <Landmark style={{ width: '26px', height: '26px', color: '#007A7C' }} />,
      image: '/app_cap_02_v4.png',
      highlights: [
        'Deep historical storytelling for global heritage sites',
        'Room-by-room & exhibit floorplan navigation',
        'Must-see artworks & opening hours schedule',
        'Curated expert tours for top world museums'
      ]
    },
    {
      id: 'mood',
      num: '07',
      badge: 'Vibe Matching',
      title: 'Mood-Based Journey Planner',
      subtitle: 'Travel Matched to How You Feel',
      desc: 'Not every trip starts with a destination: sometimes it starts with a feeling. Tell NexAround how you feel: adventurous, relaxed, romantic, curious, or hungry: and it matches the perfect vibe.',
      icon: <Sparkles style={{ width: '26px', height: '26px', color: '#007A7C' }} />,
      image: '/app_mood_planner_v4.png',
      highlights: [
        'Instant vibe selector (Relaxed, Adventure, Romantic, Foodie)',
        'Surfaces hidden experiences tailored to your energy level',
        'Adaptive suggestions matching real-time weather'
      ]
    },
    {
      id: 'radar',
      num: '08',
      badge: 'Living Spatial Map',
      title: 'Smart Maps & Location Radar',
      subtitle: 'Real-Time Attraction & Food Discovery Radar',
      desc: 'An intelligent map that goes beyond pins and directions. Layers real-time local data, saved places, Neva recommendations, and live AR data into a single interactive view.',
      icon: <MapPin style={{ width: '26px', height: '26px', color: '#007A7C' }} />,
      image: '/nexaround_app_v4.png',
      highlights: [
        'Live proximity distance radar around your GPS position',
        'Curated Food, Nature, Medical & Shopping tabs',
        'Direct ticket bookings (Viator, GetYourGuide, Headout)',
        'Real-time opening statuses & crowd levels'
      ]
    },
    {
      id: 'bookings',
      num: '09',
      badge: 'Integrated Travel Ops',
      title: 'Seamless Hotel & Taxi Bookings',
      subtitle: 'Book Stays and Rides In Journey Flow',
      desc: 'Book your stay or your ride without switching apps. NexAround integrates hotel discovery and taxi bookings directly into your itinerary flow.',
      icon: <Smartphone style={{ width: '26px', height: '26px', color: '#007A7C' }} />,
      image: '/app_download_v4.png',
      highlights: [
        'Instant hotel and transit booking confirmations',
        'Direct Uber and local transit integration',
        'Verified boutique to luxury accommodations'
      ]
    },
    {
      id: 'dining',
      num: '10',
      badge: 'Curated Experiences',
      title: 'Authentic Local Food & Discovery',
      subtitle: 'Hand-Picked Culinary and Culture Spots',
      desc: 'Beyond standard tourist spots, discover authentic local food stalls, scenic viewpoints, and cultural micro-tours handpicked by experts and verified explorers.',
      icon: <Award style={{ width: '26px', height: '26px', color: '#007A7C' }} />,
      image: '/discovery_food_tab_v4.png',
      highlights: [
        'Locally verified street food & culinary treasures',
        'Dietary and allergy filtering via Neva AI',
        'Scenic trails, hidden beaches & cultural workshops'
      ]
    }
  ];

  return (
    <div style={{ background: '#ffffff', minHeight: '100vh', paddingBottom: '80px' }}>
      
      {/* ═══════════════════════════════════════════════════════ */}
      {/* ═══ HERO SECTION (MATCHING HOME PAGE LAYOUT) ═══ */}
      <section className="hero-section" style={{ 
        position: 'relative', 
        minHeight: '75vh', 
        display: 'flex', 
        alignItems: 'center', 
        background: '#080a14', 
        overflow: 'hidden',
        padding: '170px 0 90px'
      }}>
        
        {/* Background Visual with Directional Soft Left & Bottom Vignette */}
        <div style={{
          position: 'absolute',
          top: '80px',
          left: 0,
          right: 0,
          bottom: 0,
          backgroundImage: 'url(/bg_colosseum_rome.png)',
          backgroundSize: 'cover',
          backgroundPosition: 'center 35%',
          opacity: 0.55,
          filter: 'brightness(1.1) contrast(1.05)',
          zIndex: 1,
          pointerEvents: 'none'
        }} />

        <div style={{
          position: 'absolute',
          top: '80px',
          left: 0,
          right: 0,
          bottom: 0,
          background: 'linear-gradient(90deg, rgba(8, 10, 20, 0.92) 0%, rgba(8, 10, 20, 0.62) 50%, rgba(8, 10, 20, 0.2) 100%)',
          zIndex: 2,
          pointerEvents: 'none'
        }} />

        <div style={{
          position: 'absolute',
          top: '80px',
          left: 0,
          right: 0,
          bottom: 0,
          background: 'linear-gradient(180deg, transparent 40%, rgba(8, 10, 20, 0.5) 75%, rgba(8, 10, 20, 0.98) 100%)',
          zIndex: 2,
          pointerEvents: 'none'
        }} />

        {/* Hero Content (Left-Aligned, Clean Typography Matching Home) */}
        <div className="container" style={{ position: 'relative', zIndex: 3 }}>
          <div style={{ maxWidth: '820px', textAlign: 'left' }}>
            
            {/* Main Headline */}
            <h1 style={{ 
              fontSize: 'clamp(2.6rem, 5.5vw, 4.2rem)', 
              fontWeight: 300, 
              color: '#ffffff', 
              lineHeight: 1.15, 
              letterSpacing: '-0.03em', 
              margin: '0 0 20px',
              textShadow: '0 2px 14px rgba(0,0,0,0.5)'
            }}>
              Discover What's <span style={{ fontWeight: 500, color: '#00d2d3' }}>Next Around You</span>.
            </h1>

            {/* Sub-Headline */}
            <p style={{ 
              fontSize: 'clamp(1.05rem, 1.8vw, 1.2rem)', 
              color: 'rgba(255, 255, 255, 0.88)', 
              lineHeight: 1.65, 
              margin: '0 0 38px', 
              maxWidth: '660px',
              fontWeight: 300,
              textShadow: '0 2px 10px rgba(0,0,0,0.5)'
            }}>
              An AI-powered smart tourism companion combining real-time AR camera landmark vision, Odyssey itinerary planning, and Neva 24/7 AI travel concierge.
            </p>

            {/* Action Buttons (White pill + Outline Glass) */}
            <div className="hero-btn-group" style={{ display: 'flex', gap: '14px', flexWrap: 'wrap', alignItems: 'center' }}>
              <NavLink 
                to="/get-app" 
                className="btn-white-pill"
                style={{ textDecoration: 'none' }}
              >
                <Smartphone style={{ width: '16px', height: '16px' }} />
                <span>Get App</span>
              </NavLink>

              <a 
                href="#modules" 
                onClick={(e) => { 
                  e.preventDefault(); 
                  document.getElementById('modules')?.scrollIntoView({ behavior: 'smooth' }); 
                }} 
                className="btn-glass" 
                style={{ textDecoration: 'none' }}
              >
                <span>Explore 10 Modules</span>
              </a>
            </div>

          </div>
        </div>
      </section>

      {/* ═══ BRAND STORY (3 PILLARS) ═══ */}
      <section id="story" style={{ padding: '90px 0', background: 'var(--bg-light)', borderBottom: '1px solid var(--border-color)' }}>
        <div className="container">
          
          <div style={{ textAlign: 'center', maxWidth: '720px', margin: '0 auto 56px' }}>
            <div className="badge badge-teal" style={{ marginBottom: '16px' }}>
              <Sparkles style={{ width: '14px', height: '14px' }} /> The Brand Story
            </div>
            <h2 style={{ fontSize: 'clamp(2.2rem, 4vw, 3.2rem)', fontWeight: 900, color: 'var(--dark-charcoal)', margin: '0 0 16px', letterSpacing: '-0.025em' }}>
              The Story Behind <span className="text-gradient-teal">nexARound</span>
            </h2>
            <p style={{ fontSize: '1.08rem', color: 'var(--text-secondary)', margin: 0, lineHeight: 1.7 }}>
              The name <strong>nexARound</strong> brings together three powerful ideas into one seamless travel companion.
            </p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '28px', marginBottom: '40px' }} className="grid-3">
            <div className="feature-card" style={{ padding: '36px 30px' }}>
              <span style={{ fontSize: '0.75rem', fontWeight: 800, color: 'var(--brand-teal)', textTransform: 'uppercase', letterSpacing: '1px', display: 'block', marginBottom: '10px' }}>
                01 • Discovery
              </span>
              <h3 style={{ fontSize: '1.5rem', fontWeight: 900, color: 'var(--dark-charcoal)', margin: '0 0 12px' }}>nex(t)</h3>
              <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0 }}>
                Your next adventure, your next discovery, your next unforgettable moment waiting around the corner.
              </p>
            </div>

            <div className="feature-card" style={{ padding: '36px 30px' }}>
              <span style={{ fontSize: '0.75rem', fontWeight: 800, color: 'var(--brand-teal)', textTransform: 'uppercase', letterSpacing: '1px', display: 'block', marginBottom: '10px' }}>
                02 • Surroundings
              </span>
              <h3 style={{ fontSize: '1.5rem', fontWeight: 900, color: 'var(--dark-charcoal)', margin: '0 0 12px' }}>ARound</h3>
              <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0 }}>
                Everything happening around you — from hidden cafés and scenic viewpoints to local festivals, authentic food, and culture.
              </p>
            </div>

            <div className="feature-card" style={{ padding: '36px 30px' }}>
              <span style={{ fontSize: '0.75rem', fontWeight: 800, color: 'var(--brand-teal)', textTransform: 'uppercase', letterSpacing: '1px', display: 'block', marginBottom: '10px' }}>
                03 • Technology
              </span>
              <h3 style={{ fontSize: '1.5rem', fontWeight: 900, color: 'var(--dark-charcoal)', margin: '0 0 12px' }}>Augmented Reality (AR)</h3>
              <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0 }}>
                Simply raise your phone to overlay nearby attractions, dining, shopping, and transport in real time with instant familiarity.
              </p>
            </div>
          </div>

          <div style={{
            background: 'linear-gradient(135deg, rgba(0, 122, 124, 0.08) 0%, #ffffff 50%, rgba(255, 184, 0, 0.05) 100%)',
            border: '1px solid rgba(0, 122, 124, 0.25)',
            borderRadius: 'var(--radius-lg)',
            padding: '36px 40px',
            textAlign: 'center',
            maxWidth: '960px',
            margin: '0 auto'
          }}>
            <p style={{ fontSize: '1.25rem', fontWeight: 800, color: 'var(--dark-charcoal)', margin: '0 0 8px', fontStyle: 'italic' }}>
              "What can I discover next around me, right here, right now?"
            </p>
            <p style={{ fontSize: '0.96rem', color: 'var(--brand-teal)', fontWeight: 700, margin: '0 0 16px' }}>
              Because travel isn't just about reaching a destination — it's about moments that become lifelong memories.
            </p>
            <button 
              onClick={() => setExpandedStory(!expandedStory)}
              style={{
                background: 'none',
                border: 'none',
                color: 'var(--brand-teal)',
                fontWeight: 700,
                fontSize: '0.92rem',
                cursor: 'pointer',
                display: 'inline-flex',
                alignItems: 'center',
                gap: '6px'
              }}
            >
              <span>{expandedStory ? 'Show Less' : 'Read Full Mission Statement'}</span>
              {expandedStory ? <ChevronUp style={{ width: '16px', height: '16px' }} /> : <ChevronDown style={{ width: '16px', height: '16px' }} />}
            </button>

            {expandedStory && (
              <p style={{ fontSize: '0.95rem', color: 'var(--text-secondary)', lineHeight: 1.7, marginTop: '16px', paddingTop: '16px', borderTop: '1px solid var(--border-color)', textAlign: 'left' }}>
                NexAround is an AI-powered Tourism Companion that transforms how people explore destinations across Europe, Latin America, North America, and Asia. It understands your location, mood, weather, budget, and interests to create intelligent, personalized itineraries that evolve with your journey.
              </p>
            )}
          </div>

        </div>
      </section>

      {/* ═══ 10 PRODUCT MODULES DEEP-DIVE ═══ */}
      <section id="modules" style={{ padding: '100px 0', background: '#ffffff' }}>
        <div className="container">
          
          <div style={{ textAlign: 'center', maxWidth: '700px', margin: '0 auto 64px' }}>
            <div className="badge badge-teal" style={{ marginBottom: '16px' }}>
              <Layers style={{ width: '14px', height: '14px' }} /> Complete App Capabilities
            </div>
            <h2 style={{ fontSize: 'clamp(2.2rem, 4vw, 3.2rem)', fontWeight: 900, color: 'var(--dark-charcoal)', margin: '0 0 16px', letterSpacing: '-0.025em' }}>
              10 Integrated <span className="text-gradient-teal">Feature Modules</span>
            </h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '1.08rem', margin: 0, lineHeight: 1.7 }}>
              Engineered to deliver an intelligent, effortless travel companion from the moment you plan your trip to when you step foot in the destination.
            </p>
          </div>

          {/* Module Cards Grid */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: '36px' }}>
            {appFeatures.map((mod, idx) => (
              <div 
                key={mod.id} 
                id={mod.id}
                className="feature-card" 
                style={{ 
                  scrollMarginTop: '110px',
                  padding: '48px 44px',
                  background: idx % 2 === 1 ? 'linear-gradient(135deg, rgba(0, 122, 124, 0.03) 0%, #ffffff 100%)' : '#ffffff'
                }}
              >
                <div style={{ 
                  display: 'grid', 
                  gridTemplateColumns: idx % 2 === 0 ? '1.2fr 1fr' : '1fr 1.2fr', 
                  gap: '48px', 
                  alignItems: 'center' 
                }} className="grid-2">
                  
                  {/* Left or Text Content */}
                  <div style={{ order: idx % 2 === 0 ? 1 : 2, textAlign: 'left' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '16px' }}>
                      <div style={{ width: '48px', height: '48px', borderRadius: '14px', background: 'rgba(0, 122, 124, 0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', border: '1px solid rgba(0, 122, 124, 0.25)' }}>
                        {mod.icon}
                      </div>
                      <span style={{ fontSize: '0.78rem', fontWeight: 800, color: 'var(--brand-teal)', background: 'rgba(0, 122, 124, 0.08)', padding: '6px 14px', borderRadius: '9999px', textTransform: 'uppercase', letterSpacing: '0.8px' }}>
                        Module {mod.num} • {mod.badge}
                      </span>
                    </div>

                    <h3 style={{ fontSize: 'clamp(1.8rem, 3vw, 2.3rem)', fontWeight: 900, color: 'var(--dark-charcoal)', margin: '0 0 8px', lineHeight: 1.2 }}>
                      {mod.title}
                    </h3>

                    <div style={{ fontSize: '1.02rem', fontWeight: 700, color: 'var(--brand-teal)', marginBottom: '16px' }}>
                      {mod.subtitle}
                    </div>

                    <p style={{ fontSize: '1rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: '0 0 24px' }}>
                      {mod.desc}
                    </p>

                    <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', marginBottom: '28px', paddingTop: '16px', borderTop: '1px solid var(--border-color)' }}>
                      {mod.highlights.map((h, i) => (
                        <div key={i} style={{ display: 'flex', alignItems: 'center', gap: '10px', fontSize: '0.92rem', color: 'var(--dark-charcoal)', fontWeight: 600 }}>
                          <CheckCircle2 style={{ width: '16px', height: '16px', color: 'var(--brand-teal)', flexShrink: 0 }} />
                          {h}
                        </div>
                      ))}
                    </div>

                    <NavLink to="/get-app" className="btn-teal" style={{ padding: '12px 26px', fontSize: '0.9rem', textDecoration: 'none' }}>
                      <span>Try in App</span>
                      <ArrowRight style={{ width: '16px', height: '16px' }} />
                    </NavLink>
                  </div>

                  {/* Mockup Preview */}
                  <div style={{ order: idx % 2 === 0 ? 2 : 1, display: 'flex', justifyContent: 'center' }}>
                    <div style={{
                      maxWidth: '300px',
                      borderRadius: '28px',
                      overflow: 'hidden',
                      boxShadow: '0 20px 50px rgba(10, 17, 24, 0.22)',
                      border: '6px solid #111a24',
                      background: '#111a24'
                    }}>
                      <img src={mod.image} alt={mod.title} style={{ width: '100%', height: 'auto', display: 'block' }} />
                    </div>
                  </div>

                </div>
              </div>
            ))}
          </div>

        </div>
      </section>



      {/* ═══ EXPLORE CTA ═══ */}
      <section className="container" style={{ padding: '80px 32px 0' }}>
        <div className="app-cta-card" style={{ 
          padding: '60px 44px', 
          textAlign: 'center', 
          background: 'linear-gradient(135deg, rgba(0, 122, 124, 0.08) 0%, #ffffff 50%, rgba(255, 184, 0, 0.05) 100%)', 
          border: '1px solid rgba(0, 122, 124, 0.25)',
          borderRadius: 'var(--radius-xl)',
          boxShadow: '0 20px 50px -10px rgba(0, 122, 124, 0.1)',
          maxWidth: '960px',
          margin: '0 auto'
        }}>
          <div className="badge badge-teal" style={{ marginBottom: '18px' }}>
            <Sparkles style={{ width: '14px', height: '14px' }} /> Ready to Explore?
          </div>

          <h2 style={{ fontSize: 'clamp(2.2rem, 4vw, 3.2rem)', fontWeight: 900, color: 'var(--dark-charcoal)', margin: '0 0 16px', lineHeight: 1.2 }}>
            Start Your Journey with NexAround
          </h2>

          <p style={{ color: 'var(--text-secondary)', margin: '0 auto 36px', fontSize: '1.08rem', maxWidth: '600px', lineHeight: 1.7 }}>
            Experience real-time spatial AR recognition, multi-day Odyssey planning, and 24/7 Neva AI travel assistance on your smartphone.
          </p>

          <div style={{ display: 'flex', justifyContent: 'center', gap: '16px', flexWrap: 'wrap' }}>
            <NavLink to="/get-app" className="btn-teal" style={{ padding: '16px 36px', fontSize: '1rem', textDecoration: 'none' }}>
              <Smartphone style={{ width: '18px', height: '18px' }} />
              <span>Get the NexAround App</span>
              <ArrowRight style={{ width: '16px', height: '16px' }} />
            </NavLink>
          </div>
        </div>
      </section>

    </div>
  );
}
