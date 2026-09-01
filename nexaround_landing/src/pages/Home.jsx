import { useState, useRef, useEffect } from 'react';
import { NavLink } from 'react-router-dom';
import { 
  Sparkles, Camera, Compass, MessageSquare, MapPin, 
  Landmark, Globe, BookOpen, ArrowRight, CheckCircle2, 
  Smartphone, ShieldCheck, Zap, Star, Play, ChevronRight,
  Navigation, Utensils, Award, Users, Volume2, Clock, 
  Layers, Heart, Eye, ArrowUpRight, Hotel, Car, Smile
} from 'lucide-react';
import StoreButtons from '../components/StoreButtons';

export default function Home() {
  const [activeStep, setActiveStep] = useState(0);
  const [activeScreenIndex, setActiveScreenIndex] = useState(0);
  const [selectedDestination, setSelectedDestination] = useState(0);
  const videoRef = useRef(null);

  // Ensure background video plays reliably across all browsers
  useEffect(() => {
    if (videoRef.current) {
      videoRef.current.muted = true;
      videoRef.current.defaultMuted = true;
      const playPromise = videoRef.current.play();
      if (playPromise !== undefined) {
        playPromise.catch(() => {});
      }
    }
  }, []);

  // 5 Step Workflow based on nexaround_app
  const appWorkflow = [
    {
      step: '01',
      title: 'Plan Your Odyssey Itinerary',
      subtitle: 'AI-Powered Smart Travel Planning',
      desc: 'Select your travel mood (Cultural, Adventure, Relaxed, or Foodie), input your budget, and let Odyssey craft an optimized multi-day itinerary with real-time transit and opening hours.',
      badge: 'Odyssey Engine',
      image: '/app_odyssey_planner_v4.png',
      features: [
        'Multi-day dynamic route optimization',
        'Pacing & budget customization (Backpacker to Luxury)',
        'Live transit time & museum schedule integration'
      ]
    },
    {
      step: '02',
      title: 'Scan Landmarks with Spatial AR',
      subtitle: 'Real-Time Camera Vision Recognition',
      desc: 'Point your smartphone camera at ancient monuments, heritage temples, or museum paintings. Instant computer vision identifies the landmark and displays interactive 3D historical overlays.',
      badge: 'Spatial AR Camera',
      image: '/app_scan_landmark_v4.png',
      features: [
        'Sub-second real-time camera landmark detection',
        'Interactive 3D historical context overlays',
        'Spatial contextual storytelling tailored to your vantage point'
      ]
    },
    {
      step: '03',
      title: 'Chat with Neva AI Concierge',
      subtitle: '24/7 Intelligent Local Travel Companion',
      desc: 'Meet Neva, your personal travel assistant. Ask about hidden local spots, translate foreign signs, check opening hours, or ask for dietary-safe local cuisine recommendations.',
      badge: 'Neva 24/7 AI',
      image: '/meet_neva_v4.png',
      features: [
        'Context-aware conversational assistance',
        'Conversational voice assistance & local wisdom',
        'Real-time itinerary adjustments on the go'
      ]
    },
    {
      step: '04',
      title: 'Discover with Live Radar & Map',
      subtitle: 'Proximity Attraction & Food Radar',
      desc: 'The Smart Tourism Map acts as a living radar around you. Discover hidden gems, authentic street food, verified medical centers, and book official skip-the-line tickets.',
      badge: 'Living Radar Map',
      image: '/app_maps_v4.png',
      features: [
        'Live proximity attraction & street food radar',
        'Crowd density & best visiting time indicators',
        'Direct ticket integration with Viator, GetYourGuide, Headout'
      ]
    },
    {
      step: '05',
      title: 'Archive Journal & Share Stories',
      subtitle: 'Digital Passport & Community Travel Logs',
      desc: 'Every landmark you visit automatically stamps your digital travel passport. Log personal memories, view trip stats, and discover curated stories from global explorers.',
      badge: 'Travel Passport & Feed',
      image: '/app_travel_stories_v4.png',
      features: [
        'Automatic GPS landmark passport stamping',
        'Trip milestone stats, photo logs & memory diary',
        'Community travel stories & verified creator guides'
      ]
    }
  ];

  // 10 Interactive In-App Screens from website/app.html
  const appScreens = [
    {
      num: '01',
      title: 'AR Location Discovery',
      tag: 'Augmented Reality',
      desc: 'Simply raise your phone and spin it around. NexAround overlays attractions, restaurants, cafés, shopping, hidden gems, and transport directly onto your real-world camera view.',
      image: '/app_scan_landmark_v4.png'
    },
    {
      num: '02',
      title: 'Neva AI Companion',
      tag: '24/7 Travel AI',
      desc: 'Ask Neva about what you see, where to eat, or what to do next. She understands your location, camera view, trip history, and preferences to give you one personalized answer.',
      image: '/meet_neva_v4.png'
    },
    {
      num: '03',
      title: 'Travel Stories',
      tag: 'Community Logs',
      desc: 'Discover authentic visual travel stories, photo diaries, and curated recommendations shared by fellow travelers across Europe, Asia, and the Americas.',
      image: '/app_travel_stories_v4.png'
    },
    {
      num: '04',
      title: 'Odyssey Travel Planner',
      tag: 'Smart Itineraries',
      desc: 'Tell Odyssey your destination, dates, and budget. It generates a time-optimized multi-day itinerary with verified opening hours that adapts as you explore.',
      image: '/app_cap_04_v4.png'
    },
    {
      num: '05',
      title: 'Digital Travel Journal',
      tag: 'Memory Archive',
      desc: 'Automatically captures the places you visit, landmark stamps, notes, and photos to create a personal searchable travel memoir.',
      image: '/new_journal_entry.png'
    },
    {
      num: '06',
      title: 'Curated Museum Guides',
      tag: 'Museum Guides',
      desc: 'Expert-curated exhibit walkthroughs, must-see masterworks, and museum gallery layouts for top cultural institutions worldwide.',
      image: '/app_cap_02_v4.png'
    },
    {
      num: '07',
      title: 'Mood-Based Journey Planner',
      tag: 'Vibe Matching',
      desc: 'Tell NexAround how you feel: adventurous, relaxed, romantic, curious, or hungry: and it curates experiences perfectly matched to your mood.',
      image: '/app_mood_planner_v4.png'
    },
    {
      num: '08',
      title: 'Living Tourism Maps',
      tag: 'Spatial Map',
      desc: 'An intelligent map layering real-time local data, saved places, crowd meters, and AR beacons into a unified interactive radar.',
      image: '/nexaround_app_v4.png'
    },
    {
      num: '09',
      title: 'Hotel & Taxi Bookings',
      tag: 'Integrated Bookings',
      desc: 'Confirm stays and transit without leaving the app. Seamlessly integrated with Viator, GetYourGuide, Headout, and local transit networks.',
      image: '/app_download_v4.png'
    },
    {
      num: '10',
      title: 'Curated Experiences & Dining',
      tag: 'Local Delicacies',
      desc: 'Beyond standard tourist spots, discover authentic local food stalls, scenic viewpoints, and cultural micro-tours handpicked by experts.',
      image: '/discovery_food_tab_v4.png'
    }
  ];

  // 9 World Wonders from website folder
  const destinations = [
    {
      name: 'Sigiriya Rock Fortress',
      country: 'Sri Lanka',
      image: '/bg_sigiriya.png',
      badge: 'UNESCO Heritage',
      tag: 'Ancient Citadel',
      desc: 'Explore the 5th-century palace in the sky with interactive AR fresco recognition and architectural 3D reconstruction.',
      arEnabled: true
    },
    {
      name: 'Eiffel Tower & Seine',
      country: 'Paris, France',
      image: '/bg_eiffel_tower.png',
      badge: 'Iconic Wonder',
      tag: 'Architectural Marvel',
      desc: 'Panoramic viewpoint overlays, night light timings, and historical viewpoint guides along Champ de Mars.',
      arEnabled: true
    },
    {
      name: 'Colosseum & Roman Forum',
      country: 'Rome, Italy',
      image: '/bg_colosseum_rome.png',
      badge: 'Ancient Roman',
      tag: 'Gladiator Arena',
      desc: 'Point your camera at the arena floor to see 3D reconstructions of ancient gladiatorial events and hypogeum chambers.',
      arEnabled: true
    },
    {
      name: 'Great Wall of China',
      country: 'Beijing, China',
      image: '/bg_great_wall.png',
      badge: 'World Wonder',
      tag: 'Ancient Fortress',
      desc: 'Section-by-section trail maps, watchtower histories, and optimal photography times along Mutianyu and Badaling.',
      arEnabled: true
    },
    {
      name: 'Machu Picchu Citadel',
      country: 'Cusco, Peru',
      image: '/bg_machu_picchu.png',
      badge: 'Inca Wonder',
      tag: 'Sacred Valley',
      desc: 'Step-by-step hiking route guide, astronomical temple alignments, and interactive GPS elevation mapping.',
      arEnabled: true
    },
    {
      name: 'Pyramids of Giza & Sphinx',
      country: 'Cairo, Egypt',
      image: '/bg_pyramids_giza.png',
      badge: 'Ancient Wonder',
      tag: 'Pharaoh Tombs',
      desc: 'Scan the Great Pyramid and Sphinx for architectural AR overlays and historical timeline narratives.',
      arEnabled: true
    },
    {
      name: 'Taj Mahal Monument',
      country: 'Agra, India',
      image: '/bg_taj_mahal.png',
      badge: 'Mughal Architecture',
      tag: 'Marble Wonder',
      desc: 'Discover symmetry secrets, calligraphy translations, and optimal sunrise photography spots.',
      arEnabled: true
    },
    {
      name: 'Statue of Liberty',
      country: 'New York, USA',
      image: '/bg_statue_liberty.png',
      badge: 'Historic Harbor',
      tag: 'Freedom Icon',
      desc: 'Harbor viewpoint guide, crown access tips, and interactive historical timeline of Ellis Island.',
      arEnabled: true
    },
    {
      name: 'Sydney Opera House',
      country: 'Sydney, Australia',
      image: '/bg_sydney_opera.png',
      badge: 'Modern Wonder',
      tag: 'Harbor Landmark',
      desc: 'Acoustic architecture breakdown, walking tours, and harbor ferry schedule integrations.',
      arEnabled: true
    }
  ];

  return (
    <div style={{ background: '#ffffff', minHeight: '100vh', overflowX: 'hidden' }}>
      
      {/* ═══════════════════════════════════════════════════════ */}
      {/* ═══ HERO SECTION (MATCHING REFERENCE LAYOUT - 100VH) ═══ */}
      <section className="hero-section" style={{ 
        position: 'relative', 
        background: '#080a14', 
        overflow: 'hidden'
      }}>
        
        {/* Background Travel Video */}
        <video
          ref={videoRef}
          autoPlay
          loop
          muted
          playsInline
          poster="/homepage_video_poster.jpg"
          style={{
            position: 'absolute',
            top: 0,
            left: 0,
            width: '100%',
            height: '100%',
            objectFit: 'cover',
            objectPosition: 'center 20%',
            zIndex: 1,
            opacity: 1,
            filter: 'brightness(1.15) contrast(1.05)',
            pointerEvents: 'none'
          }}
        >
          <source src="/nexaround_hero.mp4" type="video/mp4" />
        </video>

        {/* Directional Soft Left & Bottom Vignette */}
        <div style={{
          position: 'absolute',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          background: 'linear-gradient(90deg, rgba(8, 10, 20, 0.78) 0%, rgba(8, 10, 20, 0.48) 45%, rgba(8, 10, 20, 0.12) 100%)',
          zIndex: 2,
          pointerEvents: 'none'
        }} />

        <div style={{
          position: 'absolute',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          background: 'linear-gradient(180deg, transparent 40%, rgba(8, 10, 20, 0.4) 75%, rgba(8, 10, 20, 0.98) 100%)',
          zIndex: 2,
          pointerEvents: 'none'
        }} />

        {/* Hero Content (Left-Aligned, Clean Typography Matching Reference) */}
        <div className="container" style={{ position: 'relative', zIndex: 3 }}>
          <div style={{ maxWidth: '820px', textAlign: 'left' }}>
            
            {/* Main Headline */}
            <h1 style={{ 
              fontSize: 'clamp(2.8rem, 6vw, 4.6rem)', 
              fontWeight: 300, 
              color: '#ffffff', 
              lineHeight: 1.15, 
              letterSpacing: '-0.03em', 
              margin: '0 0 20px',
              textShadow: '0 2px 14px rgba(0,0,0,0.5)'
            }}>
              Explore the World with <span style={{ fontWeight: 500, color: '#00d2d3' }}>Spatial AI</span>.
            </h1>

            {/* Sub-Headline */}
            <p style={{ 
              fontSize: 'clamp(1.05rem, 1.8vw, 1.22rem)', 
              color: 'rgba(255, 255, 255, 0.88)', 
              lineHeight: 1.65, 
              margin: '0 0 38px', 
              maxWidth: '660px',
              fontWeight: 300,
              textShadow: '0 2px 10px rgba(0,0,0,0.5)'
            }}>
              Point your camera to recognize ancient ruins & landmarks in real-time, generate personalized Odyssey itineraries, and chat with Neva- your 24/7 AI travel concierge.
            </p>

            {/* Action Buttons */}
            <div className="hero-btn-group" style={{ display: 'flex', gap: '14px', flexWrap: 'wrap', alignItems: 'center' }}>
              <NavLink 
                to="/get-app" 
                style={{ 
                  background: '#ffffff', 
                  color: '#000000', 
                  padding: '14px 28px', 
                  borderRadius: '9999px', 
                  fontSize: '15px', 
                  fontWeight: 500, 
                  display: 'inline-flex', 
                  alignItems: 'center', 
                  gap: '8px', 
                  textDecoration: 'none',
                  boxShadow: '0 4px 20px rgba(0,0,0,0.25)',
                  transition: 'all 0.25s ease'
                }}
                onMouseEnter={(e) => { e.currentTarget.style.transform = 'translateY(-2px)'; }}
                onMouseLeave={(e) => { e.currentTarget.style.transform = 'translateY(0)'; }}
              >
                <span>Get the App</span>
                <ArrowRight style={{ width: '15px', height: '15px' }} />
              </NavLink>

              <a 
                href="#features" 
                style={{ 
                  background: 'rgba(255, 255, 255, 0.08)', 
                  color: '#ffffff', 
                  border: '1.5px solid rgba(255, 255, 255, 0.45)', 
                  padding: '14px 28px', 
                  borderRadius: '9999px', 
                  fontSize: '15px', 
                  fontWeight: 500, 
                  display: 'inline-flex', 
                  alignItems: 'center', 
                  gap: '8px', 
                  textDecoration: 'none',
                  backdropFilter: 'blur(8px)',
                  WebkitBackdropFilter: 'blur(8px)',
                  transition: 'all 0.25s ease'
                }}
                onMouseEnter={(e) => { e.currentTarget.style.background = 'rgba(255, 255, 255, 0.16)'; e.currentTarget.style.transform = 'translateY(-2px)'; }}
                onMouseLeave={(e) => { e.currentTarget.style.background = 'rgba(255, 255, 255, 0.08)'; e.currentTarget.style.transform = 'translateY(0)'; }}
              >
                <span>Explore Features</span>
              </a>
            </div>

          </div>
        </div>

      </section>

      {/* ══════════════════════════════════════════════════════════
          2. THE BRAND STORY: 3 PILLARS (FROM WEBSITE FOLDER)
          ══════════════════════════════════════════════════════════ */}
      <section id="story" className="section-padding" style={{ background: 'var(--bg-light)', borderBottom: '1px solid var(--border-color)' }}>
        <div className="container">
          
          <div style={{ textAlign: 'center', maxWidth: '720px', margin: '0 auto 56px' }}>
            <div className="badge badge-teal" style={{ marginBottom: '16px' }}>
              <Sparkles style={{ width: '14px', height: '14px' }} /> The Brand Story
            </div>
            <h2 style={{ fontSize: 'clamp(2.2rem, 4vw, 3.2rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 16px', letterSpacing: '-0.025em' }}>
              The Story Behind <span className="text-gradient-teal">nexARound</span>
            </h2>
            <p style={{ fontSize: '1.08rem', color: 'var(--text-secondary)', margin: 0, lineHeight: 1.7 }}>
              The name <strong>nexARound</strong> brings together three foundational ideas into one seamless travel companion.
            </p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '28px', marginBottom: '48px' }} className="grid-3">
            
            {/* Pillar 1 */}
            <div className="feature-card" style={{ textAlign: 'left', padding: '36px 30px' }}>
              <span style={{ fontSize: '0.75rem', fontWeight: 500, color: 'var(--brand-teal)', textTransform: 'uppercase', letterSpacing: '1px', display: 'block', marginBottom: '10px' }}>
                01 • Discovery
              </span>
              <h3 style={{ fontSize: '1.5rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 12px' }}>
                nex(t)
              </h3>
              <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0 }}>
                Your next adventure, your next discovery, your next unforgettable moment waiting around the corner.
              </p>
            </div>

            {/* Pillar 2 */}
            <div className="feature-card" style={{ textAlign: 'left', padding: '36px 30px' }}>
              <span style={{ fontSize: '0.75rem', fontWeight: 500, color: 'var(--brand-teal)', textTransform: 'uppercase', letterSpacing: '1px', display: 'block', marginBottom: '10px' }}>
                02 • Surroundings
              </span>
              <h3 style={{ fontSize: '1.5rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 12px' }}>
                ARound
              </h3>
              <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0 }}>
                Everything happening around you- from hidden cafés and scenic viewpoints to local festivals, authentic food, and culture.
              </p>
            </div>

            {/* Pillar 3 */}
            <div className="feature-card" style={{ textAlign: 'left', padding: '36px 30px' }}>
              <span style={{ fontSize: '0.75rem', fontWeight: 500, color: 'var(--brand-teal)', textTransform: 'uppercase', letterSpacing: '1px', display: 'block', marginBottom: '10px' }}>
                03 • Technology
              </span>
              <h3 style={{ fontSize: '1.5rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 12px' }}>
                Augmented Reality (AR)
              </h3>
              <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0 }}>
                Simply raise your phone to overlay nearby attractions, dining, shopping, and transport in real time with instant familiarity.
              </p>
            </div>

          </div>

          {/* Mission Quote Banner */}
          <div style={{
            background: 'linear-gradient(135deg, rgba(0, 122, 124, 0.08) 0%, #ffffff 50%, rgba(255, 184, 0, 0.05) 100%)',
            border: '1px solid rgba(0, 122, 124, 0.25)',
            borderRadius: 'var(--radius-lg)',
            padding: '36px 40px',
            textAlign: 'center',
            maxWidth: '960px',
            margin: '0 auto'
          }}>
            <p style={{ fontSize: '1.25rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 8px', fontStyle: 'italic' }}>
              "What can I discover next around me, right here, right now?"
            </p>
            <p style={{ fontSize: '0.96rem', color: 'var(--brand-teal)', fontWeight: 500, margin: 0 }}>
              Because travel isn't just about reaching a destination- it's about moments that become lifelong memories.
            </p>
          </div>

        </div>
      </section>

      {/* ══════════════════════════════════════════════════════════
          3. "HOW THE APP WORKS"- STEP-BY-STEP INTERACTIVE WORKFLOW
          ══════════════════════════════════════════════════════════ */}
      <section id="how-it-works" className="section-padding" style={{ background: '#ffffff', position: 'relative' }}>
        <div className="container">
          
          <div style={{ textAlign: 'center', maxWidth: '760px', margin: '0 auto 64px' }}>
            <div className="badge badge-teal" style={{ marginBottom: '16px' }}>
              <Zap style={{ width: '14px', height: '14px' }} /> Intuitive Travel Workflow
            </div>
            <h2 style={{ fontSize: 'clamp(2.2rem, 4vw, 3.2rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 16px', letterSpacing: '-0.025em' }}>
              How <span className="text-gradient-teal">NexAround</span> Works
            </h2>
            <p style={{ fontSize: '1.08rem', color: 'var(--text-secondary)', margin: 0, lineHeight: 1.7 }}>
              From planning your journey to exploring real-world monuments and logging your travel memories, here is how the mobile ecosystem guides your adventure every step of the way.
            </p>
          </div>

          {/* Workflow Steps Horizontal Tab Strip */}
          <div style={{ 
            display: 'flex', 
            gap: '10px', 
            overflowX: 'auto', 
            paddingBottom: '16px', 
            marginBottom: '48px', 
            justifyContent: 'center',
            flexWrap: 'wrap'
          }}>
            {appWorkflow.map((item, idx) => (
              <button
                key={idx}
                onClick={() => setActiveStep(idx)}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: '10px',
                  padding: '12px 22px',
                  borderRadius: '9999px',
                  border: activeStep === idx ? '2px solid var(--brand-teal)' : '1px solid var(--border-color)',
                  background: activeStep === idx ? 'var(--brand-teal-soft)' : '#ffffff',
                  color: activeStep === idx ? 'var(--brand-teal)' : 'var(--text-secondary)',
                  cursor: 'pointer',
                  fontWeight: 500,
                  fontSize: '0.9rem',
                  transition: 'all 0.25s ease',
                  boxShadow: activeStep === idx ? '0 4px 16px rgba(0, 122, 124, 0.15)' : 'none'
                }}
              >
                <span style={{ 
                  width: '24px', 
                  height: '24px', 
                  borderRadius: '50%', 
                  background: activeStep === idx ? 'var(--brand-teal)' : 'var(--bg-surface)', 
                  color: activeStep === idx ? '#ffffff' : 'var(--text-muted)', 
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: '0.75rem',
                  fontWeight: 500
                }}>
                  {item.step}
                </span>
                <span>{item.title}</span>
              </button>
            ))}
          </div>

          {/* Active Step Showcase Card */}
          <div style={{
            background: 'linear-gradient(135deg, rgba(0, 122, 124, 0.04) 0%, #ffffff 50%, rgba(248, 250, 252, 0.8) 100%)',
            border: '1px solid rgba(0, 122, 124, 0.22)',
            borderRadius: 'var(--radius-xl)',
            padding: '48px 44px',
            boxShadow: '0 20px 50px -10px rgba(0, 122, 124, 0.08)'
          }}>
            <div style={{ display: 'grid', gridTemplateColumns: '1.1fr 1fr', gap: '48px', alignItems: 'center' }} className="grid-2">
              
              {/* Left Details */}
              <div style={{ textAlign: 'left' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '18px' }}>
                  <span style={{ fontSize: '0.8rem', fontWeight: 500, color: 'var(--brand-teal)', background: 'rgba(0, 122, 124, 0.1)', padding: '6px 14px', borderRadius: '9999px', textTransform: 'uppercase', letterSpacing: '0.8px' }}>
                    Step {appWorkflow[activeStep].step} • {appWorkflow[activeStep].badge}
                  </span>
                </div>

                <h3 style={{ fontSize: 'clamp(1.8rem, 3.2vw, 2.5rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 12px', lineHeight: 1.2 }}>
                  {appWorkflow[activeStep].title}
                </h3>
                
                <div style={{ fontSize: '1.05rem', fontWeight: 500, color: 'var(--brand-teal)', marginBottom: '18px' }}>
                  {appWorkflow[activeStep].subtitle}
                </div>

                <p style={{ fontSize: '1.02rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: '0 0 28px' }}>
                  {appWorkflow[activeStep].desc}
                </p>

                {/* Feature Bullet Points */}
                <div style={{ display: 'flex', flexDirection: 'column', gap: '14px', marginBottom: '36px' }}>
                  {appWorkflow[activeStep].features.map((feat, i) => (
                    <div key={i} style={{ display: 'flex', alignItems: 'flex-start', gap: '12px' }}>
                      <div style={{ width: '22px', height: '22px', borderRadius: '50%', background: 'rgba(0, 122, 124, 0.12)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, marginTop: '2px' }}>
                        <CheckCircle2 style={{ width: '15px', height: '15px', color: 'var(--brand-teal)' }} />
                      </div>
                      <span style={{ fontSize: '0.96rem', fontWeight: 500, color: 'var(--dark-charcoal)' }}>{feat}</span>
                    </div>
                  ))}
                </div>

                <div style={{ display: 'flex', gap: '14px' }}>
                  <NavLink to="/app" className="btn-teal">
                    <span>Explore This Module</span>
                    <ArrowRight style={{ width: '16px', height: '16px' }} />
                  </NavLink>
                  {activeStep < appWorkflow.length - 1 && (
                    <button onClick={() => setActiveStep(prev => prev + 1)} className="btn-secondary">
                      Next Step <ChevronRight style={{ width: '16px', height: '16px' }} />
                    </button>
                  )}
                </div>
              </div>

              {/* Right App Screen Mockup */}
              <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', position: 'relative' }}>
                <div style={{
                  position: 'relative',
                  zIndex: 2,
                  maxWidth: '320px',
                  borderRadius: '32px',
                  overflow: 'hidden',
                  boxShadow: '0 25px 60px -15px rgba(10, 17, 24, 0.3), 0 0 30px rgba(0, 122, 124, 0.15)',
                  border: '8px solid #111a24',
                  background: '#111a24'
                }}>
                  <img
                    src={appWorkflow[activeStep].image}
                    alt={appWorkflow[activeStep].title}
                    style={{ width: '100%', height: 'auto', display: 'block' }}
                  />
                </div>
              </div>

            </div>
          </div>

        </div>
      </section>

      {/* ══════════════════════════════════════════════════════════
          4. 10 INTERACTIVE IN-APP SCREENS (FROM WEBSITE/APP.HTML)
          ══════════════════════════════════════════════════════════ */}
      <section className="section-padding" style={{ background: 'var(--bg-light)', borderTop: '1px solid var(--border-color)', borderBottom: '1px solid var(--border-color)' }}>
        <div className="container">
          
          <div style={{ textAlign: 'center', maxWidth: '760px', margin: '0 auto 60px' }}>
            <div className="badge badge-teal" style={{ marginBottom: '16px' }}>
              <Layers style={{ width: '14px', height: '14px' }} /> Inside the App
            </div>
            <h2 style={{ fontSize: 'clamp(2.2rem, 4vw, 3.2rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 16px', letterSpacing: '-0.025em' }}>
              10 Screens, <span className="text-gradient-teal">One Unified Experience</span>
            </h2>
            <p style={{ fontSize: '1.08rem', color: 'var(--text-secondary)', margin: 0, lineHeight: 1.7 }}>
              Tap any feature below to view its live screen mockup and explore the full mobile capabilities.
            </p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1.4fr 1fr', gap: '48px', alignItems: 'center' }} className="grid-2">
            
            {/* Left: 10 Feature Buttons List */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
              {appScreens.map((screen, idx) => (
                <button
                  key={idx}
                  onClick={() => setActiveScreenIndex(idx)}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: '16px',
                    padding: '16px 20px',
                    borderRadius: 'var(--radius-md)',
                    background: activeScreenIndex === idx ? 'var(--brand-teal)' : '#ffffff',
                    color: activeScreenIndex === idx ? '#ffffff' : 'var(--dark-charcoal)',
                    border: activeScreenIndex === idx ? '1px solid var(--brand-teal)' : '1px solid var(--border-color)',
                    cursor: 'pointer',
                    transition: 'all 0.25s ease',
                    textAlign: 'left',
                    boxShadow: activeScreenIndex === idx ? 'var(--shadow-teal)' : 'var(--shadow-sm)'
                  }}
                >
                  <span style={{
                    fontSize: '0.85rem',
                    fontWeight: 500,
                    color: activeScreenIndex === idx ? '#00d2d3' : 'var(--brand-teal)',
                    fontFamily: 'var(--font-mono)',
                    width: '28px'
                  }}>
                    {screen.num}
                  </span>
                  
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: '1rem', fontWeight: 500 }}>{screen.title}</div>
                  </div>

                  <ChevronRight style={{ width: '18px', height: '18px', color: activeScreenIndex === idx ? '#ffffff' : 'var(--text-muted)' }} />
                </button>
              ))}
            </div>

            {/* Right: Active Screen Phone Mockup */}
            <div className="sticky-mockup" style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', position: 'sticky', top: '100px' }}>
              <div style={{
                position: 'relative',
                maxWidth: '320px',
                width: '100%',
                borderRadius: '34px',
                overflow: 'hidden',
                boxShadow: '0 30px 70px -15px rgba(10, 17, 24, 0.35), 0 0 35px rgba(0, 122, 124, 0.2)',
                border: '8px solid #111a24',
                background: '#111a24'
              }}>
                <img
                  src={appScreens[activeScreenIndex].image}
                  alt={appScreens[activeScreenIndex].title}
                  style={{ width: '100%', height: 'auto', display: 'block' }}
                />
              </div>
            </div>

          </div>

        </div>
      </section>

      {/* ══════════════════════════════════════════════════════════
          5. 9 WORLD WONDERS & AR SIGHTSEEING SHOWCASE
          ══════════════════════════════════════════════════════════ */}
      <section className="dark-section section-padding" style={{ position: 'relative', overflow: 'hidden' }}>
        
        {/* Ambient Teal Radial */}
        <div style={{
          position: 'absolute',
          top: '20%',
          right: '5%',
          width: '500px',
          height: '500px',
          background: 'radial-gradient(circle, rgba(0, 122, 124, 0.22) 0%, rgba(10, 17, 24, 0) 70%)',
          pointerEvents: 'none'
        }} />

        <div className="container" style={{ position: 'relative', zIndex: 2 }}>
          
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginBottom: '56px', flexWrap: 'wrap', gap: '24px' }}>
            <div style={{ maxWidth: '640px', textAlign: 'left' }}>
              <div className="badge badge-teal-glow" style={{ marginBottom: '16px' }}>
                <Globe style={{ width: '14px', height: '14px' }} /> Global Sightseeing Library
              </div>
              <h2 style={{ fontSize: 'clamp(2.2rem, 3.8vw, 3.2rem)', fontWeight: 500, color: '#ffffff', margin: 0, letterSpacing: '-0.025em' }}>
                World Landmarks Ready for <span className="text-gradient-teal">AR Discovery</span>
              </h2>
            </div>
            
            <NavLink to="/app" className="btn-glass">
              <span>Explore All 50+ Cities</span>
              <ChevronRight style={{ width: '16px', height: '16px' }} />
            </NavLink>
          </div>

          {/* Destinations Grid */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '28px' }} className="grid-3">
            {destinations.map((dest, i) => (
              <div 
                key={i} 
                className="dark-card" 
                style={{ 
                  padding: 0, 
                  overflow: 'hidden', 
                  cursor: 'pointer',
                  border: selectedDestination === i ? '1px solid #00d2d3' : '1px solid var(--dark-border)'
                }}
                onClick={() => setSelectedDestination(i)}
              >
                {/* Image Container with Badge */}
                <div style={{ position: 'relative', height: '240px', overflow: 'hidden' }}>
                  <img
                    src={dest.image}
                    alt={dest.name}
                    style={{
                      width: '100%',
                      height: '100%',
                      objectFit: 'cover',
                      transition: 'transform 0.4s ease'
                    }}
                    onMouseEnter={(e) => e.currentTarget.style.transform = 'scale(1.06)'}
                    onMouseLeave={(e) => e.currentTarget.style.transform = 'scale(1)'}
                  />
                  
                  <div style={{
                    position: 'absolute',
                    top: '16px',
                    left: '16px',
                    background: 'rgba(10, 17, 24, 0.75)',
                    backdropFilter: 'blur(8px)',
                    border: '1px solid rgba(255, 255, 255, 0.2)',
                    borderRadius: '9999px',
                    padding: '4px 12px',
                    fontSize: '0.72rem',
                    fontWeight: 500,
                    color: '#00d2d3'
                  }}>
                    {dest.badge}
                  </div>

                  {dest.arEnabled && (
                    <div style={{
                      position: 'absolute',
                      bottom: '16px',
                      right: '16px',
                      background: 'rgba(0, 122, 124, 0.85)',
                      backdropFilter: 'blur(8px)',
                      borderRadius: '9999px',
                      padding: '4px 12px',
                      fontSize: '0.72rem',
                      fontWeight: 500,
                      color: '#ffffff',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '6px'
                    }}>
                      <Camera style={{ width: '12px', height: '12px' }} /> AR Available
                    </div>
                  )}
                </div>

                {/* Content */}
                <div style={{ padding: '24px', textAlign: 'left' }}>
                  <div style={{ fontSize: '0.75rem', fontWeight: 500, color: 'rgba(255, 255, 255, 0.6)', textTransform: 'uppercase', letterSpacing: '0.8px', marginBottom: '6px' }}>
                    {dest.country} • {dest.tag}
                  </div>
                  <h3 style={{ fontSize: '1.25rem', fontWeight: 500, color: '#ffffff', margin: '0 0 10px' }}>
                    {dest.name}
                  </h3>
                  <p style={{ fontSize: '0.88rem', color: 'rgba(255, 255, 255, 0.75)', lineHeight: 1.65, margin: 0 }}>
                    {dest.desc}
                  </p>
                </div>
              </div>
            ))}
          </div>

        </div>
      </section>

      {/* ══════════════════════════════════════════════════════════
          6. TRAVEL INTEGRATION PARTNERS BAR
          ══════════════════════════════════════════════════════════ */}
      <section style={{ padding: '50px 0', background: '#ffffff', borderBottom: '1px solid var(--border-color)' }}>
        <div className="container">
          <div style={{ textAlign: 'center', marginBottom: '28px' }}>
            <span style={{ fontSize: '0.76rem', fontWeight: 500, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '1.2px' }}>
              Integrated with Top Global Booking & Transit Networks
            </span>
          </div>

          <div className="partner-logos-row" style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', gap: '36px', flexWrap: 'wrap', opacity: 0.85 }}>
            <img src="/booking.svg" alt="Booking.com Integration" style={{ height: '18px', objectFit: 'contain' }} onError={(e) => { e.currentTarget.style.display = 'none'; }} />
            <img src="/viator.png" alt="Viator Integration" style={{ height: '24px', objectFit: 'contain' }} onError={(e) => { e.currentTarget.style.display = 'none'; }} />
            <img src="/getyourguide.png" alt="GetYourGuide Integration" style={{ height: '28px', objectFit: 'contain' }} onError={(e) => { e.currentTarget.style.display = 'none'; }} />
            <img src="/headout.png" alt="Headout Integration" style={{ height: '26px', objectFit: 'contain' }} onError={(e) => { e.currentTarget.style.display = 'none'; }} />
            <img src="/skyscanner.png" alt="Skyscanner Integration" style={{ height: '24px', objectFit: 'contain' }} onError={(e) => { e.currentTarget.style.display = 'none'; }} />
            <img src="/uber_logo.png" alt="Uber Integration" style={{ height: '22px', objectFit: 'contain' }} onError={(e) => { e.currentTarget.style.display = 'none'; }} />
          </div>
        </div>
      </section>

      {/* ══════════════════════════════════════════════════════════
          7. MEET NEVA- 24/7 AI TRAVEL CONCIERGE SPOTLIGHT
          ══════════════════════════════════════════════════════════ */}
      <section className="section-padding" style={{ background: '#ffffff', position: 'relative' }}>
        <div className="container">
          
          <div className="neva-spotlight-card" style={{
            background: 'linear-gradient(135deg, rgba(0, 122, 124, 0.08) 0%, #ffffff 60%, rgba(255, 184, 0, 0.05) 100%)',
            border: '1px solid rgba(0, 122, 124, 0.25)',
            borderRadius: 'var(--radius-xl)',
            padding: '56px 48px',
            boxShadow: '0 20px 60px -10px rgba(0, 122, 124, 0.1)'
          }}>
            <div style={{ display: 'grid', gridTemplateColumns: '1.1fr 1fr', gap: '52px', alignItems: 'center' }} className="grid-2">
              
              {/* Left Info */}
              <div style={{ textAlign: 'left' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '20px' }}>
                  <div style={{ width: '44px', height: '44px', borderRadius: '12px', background: 'var(--brand-teal)', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 4px 16px rgba(0,122,124,0.3)' }}>
                    <img src="/neva_avatar.png" alt="Neva Avatar" style={{ width: '32px', height: '32px', borderRadius: '50%' }} onError={(e) => { e.currentTarget.style.display = 'none'; }} />
                  </div>
                  <div>
                    <div style={{ fontSize: '0.75rem', fontWeight: 500, color: 'var(--brand-teal)', textTransform: 'uppercase', letterSpacing: '1px' }}>Meet Neva</div>
                    <div style={{ fontSize: '1.2rem', fontWeight: 500, color: 'var(--dark-charcoal)' }}>Your AI Travel Concierge</div>
                  </div>
                </div>

                <h2 style={{ fontSize: 'clamp(2rem, 3.5vw, 2.8rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 16px', lineHeight: 1.2 }}>
                  Always by Your Side, Wherever You Explore.
                </h2>

                <p style={{ fontSize: '1.05rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: '0 0 28px' }}>
                  Trained on authentic cultural knowledge and destination telemetry, Neva understands context. Ask questions in natural speech or text, and get instant answers formatted specifically for travelers.
                </p>

                {/* Sample Prompt Chips */}
                <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', marginBottom: '32px' }}>
                  {[
                    '“Find me the best authentic seafood street spot within 10 mins walk”',
                    '“Translate this museum inscription and explain the dynasty background”',
                    '“It started raining. Re-route my afternoon for indoor galleries”',
                  ].map((prompt, idx) => (
                    <div key={idx} style={{ 
                      background: '#ffffff', 
                      border: '1px solid rgba(0, 122, 124, 0.2)', 
                      borderRadius: '12px', 
                      padding: '12px 18px', 
                      fontSize: '0.92rem', 
                      fontWeight: 500, 
                      color: 'var(--dark-charcoal)',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '10px',
                      boxShadow: '0 2px 8px rgba(0, 122, 124, 0.04)'
                    }}>
                      <MessageSquare style={{ width: '16px', height: '16px', color: 'var(--brand-teal)', flexShrink: 0 }} />
                      <span>{prompt}</span>
                    </div>
                  ))}
                </div>

                <a href="#download" className="btn-teal">
                  <span>Chat with Neva on Mobile</span>
                  <ArrowRight style={{ width: '16px', height: '16px' }} />
                </a>
              </div>

              {/* Right Mockup */}
              <div style={{ display: 'flex', justifyContent: 'center' }}>
                <div style={{
                  maxWidth: '310px',
                  borderRadius: '30px',
                  overflow: 'hidden',
                  boxShadow: '0 25px 60px rgba(10, 17, 24, 0.25)',
                  border: '6px solid #111a24',
                  background: '#111a24'
                }}>
                  <img src="/meet_neva_v4.png" alt="Neva AI Chat Screen" style={{ width: '100%', height: 'auto', display: 'block' }} />
                </div>
              </div>

            </div>
          </div>

        </div>
      </section>

      {/* ══════════════════════════════════════════════════════════
          8. DOWNLOAD & GET THE APP CTA SECTION (WITH 3D SHOWCASE)
          ══════════════════════════════════════════════════════════ */}
      <section id="download" style={{ padding: '100px 0', background: 'var(--dark-charcoal)', position: 'relative', overflow: 'hidden' }}>
        
        {/* Glow */}
        <div style={{
          position: 'absolute',
          top: '50%',
          left: '50%',
          transform: 'translate(-50%, -50%)',
          width: '750px',
          height: '450px',
          background: 'radial-gradient(circle, rgba(0, 122, 124, 0.3) 0%, rgba(10, 17, 24, 0) 70%)',
          pointerEvents: 'none'
        }} />

        <div className="container" style={{ position: 'relative', zIndex: 2 }}>
          <div className="download-showcase-card" style={{
            background: 'rgba(17, 26, 36, 0.92)',
            border: '1px solid rgba(0, 122, 124, 0.4)',
            borderRadius: 'var(--radius-xl)',
            padding: '64px 48px',
            boxShadow: '0 25px 70px rgba(0, 0, 0, 0.6), 0 0 40px rgba(0, 122, 124, 0.2)'
          }}>
            <div style={{ display: 'grid', gridTemplateColumns: '1.2fr 1fr', gap: '52px', alignItems: 'center' }} className="grid-2">
              
              {/* Left CTA Info */}
              <div style={{ textAlign: 'left' }}>
                <div className="badge badge-teal-glow" style={{ marginBottom: '18px' }}>
                  <Sparkles style={{ width: '14px', height: '14px' }} /> Free to Start • No Itinerary Required
                </div>

                <h2 style={{ fontSize: 'clamp(2.2rem, 4vw, 3.2rem)', fontWeight: 500, color: '#ffffff', margin: '0 0 16px', lineHeight: 1.15 }}>
                  Your Intelligent Journey <br />
                  <span className="text-gradient-teal">Starts Right Here.</span>
                </h2>

                <p style={{ fontSize: '1.08rem', color: 'rgba(255, 255, 255, 0.82)', lineHeight: 1.7, margin: '0 0 36px', maxWidth: '540px' }}>
                  Available on iOS and Android. Download the NexAround mobile application today and explore destinations across Europe, Asia, and the Americas.
                </p>

                {/* Store Download Buttons */}
                <div style={{ marginBottom: '32px', display: 'flex', justifyContent: 'flex-start' }}>
                  <StoreButtons theme="onDark" showRating={false} />
                </div>

                {/* Trust Badges */}
                <div style={{ display: 'flex', gap: '24px', flexWrap: 'wrap', paddingTop: '20px', borderTop: '1px solid rgba(255, 255, 255, 0.12)' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: '#ffffff', fontSize: '0.86rem', fontWeight: 500 }}>
                    <ShieldCheck style={{ width: '18px', height: '18px', color: '#00d2d3' }} />
                    <span>100% Free to Download</span>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: '#ffffff', fontSize: '0.86rem', fontWeight: 500 }}>
                    <Zap style={{ width: '18px', height: '18px', color: '#00d2d3' }} />
                    <span>Instant Setup • No Credit Card</span>
                  </div>
                </div>
              </div>

              {/* Right Showcase 3D Mockup */}
              <div style={{ display: 'flex', justifyContent: 'center' }}>
                <div style={{
                  maxWidth: '480px',
                  width: '100%',
                  borderRadius: '24px',
                  overflow: 'hidden',
                  boxShadow: '0 25px 60px rgba(0, 0, 0, 0.8), 0 0 35px rgba(0, 122, 124, 0.3)',
                  border: '1px solid rgba(255, 255, 255, 0.15)'
                }}>
                  <img src="/app_download_showcase.png" alt="NexAround App 3D Showcase" style={{ width: '100%', height: 'auto', display: 'block' }} />
                </div>
              </div>

            </div>
          </div>
        </div>

      </section>

    </div>
  );
}
