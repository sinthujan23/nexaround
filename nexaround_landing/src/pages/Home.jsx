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
import AppScreen from '../components/AppScreen';
import { APP_MODULES } from '../data/appModules';

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
      title: 'Plan Your Trip with Odyssey',
      subtitle: 'AI Trip Planning',
      desc: 'Enter a destination, dates, travellers and budget, and Odyssey builds a complete day-by-day plan with flights, stays, a budget breakdown and visa guidance.',
      badge: 'Odyssey AI Planner',
      image: '/app_odyssey_plans_v4.png',
      features: [
        'Day-by-day plans for one city or several',
        'Flight and hotel options with partner booking links',
        'Budget breakdown, visa guidance and booking timeline'
      ]
    },
    {
      step: '02',
      title: 'Point Your Phone with AR',
      subtitle: 'See What Is Around You',
      desc: 'Hold up your phone and look around to see nearby places over the camera view. Point at a place and nexARound uses your location and compass to show what it is, then tap Neva to learn more.',
      badge: 'AR Discovery',
      image: '/app_scan_landmark_v4.png',
      features: [
        'Place labels for food, shopping, hotels, nature and more',
        'Ask Neva about the place you point at',
        'Walking routes with direction arrows in the camera view'
      ]
    },
    {
      step: '03',
      title: 'Chat or Talk with Neva',
      subtitle: 'Your AI Travel Companion',
      desc: 'Ask Neva about places, food, history, budgets or what to do next, and get answers based on your location. Type or talk, and Neva shows the places she suggests on a map.',
      badge: 'Neva AI',
      image: '/meet_neva_v4.png',
      features: [
        'Answers based on where you are',
        'Voice chat with replies read aloud',
        'Suggested places shown on a map'
      ]
    },
    {
      step: '04',
      title: 'Follow a City Guide',
      subtitle: 'Day-by-Day Guides with Navigation',
      desc: 'Pick a city guide, choose how many days you have and follow it stop by stop. Press Start for live directions, including which public transport line to take.',
      badge: 'City Guides',
      image: '/app_city_guides.png',
      features: [
        'Guides written by creators and reviewed by nexARound',
        'Plan by day or by place',
        'Live navigation with public transport directions'
      ]
    },
    {
      step: '05',
      title: 'Share Stories and Keep a Journal',
      subtitle: 'Travel Stories & Community',
      desc: 'Read stories from travellers near you, post your own with photos, ask the Travel Forum and keep a private journal of every trip.',
      badge: 'Stories & Journal',
      image: '/app_travel_stories_v4.png',
      features: [
        'Stories near you first, or by country',
        'Travel Forum for questions and answers',
        'Private journal with notes, spending and photos'
      ]
    }
  ];

  // The app's features, shared with the App page (src/data/appModules.js)
  const appScreens = APP_MODULES.map((m, i) => ({
    ...m,
    num: String(i + 1).padStart(2, '0'),
    tag: m.badge,
  }));

  // 9 World Wonders from website folder
  const destinations = [
    {
      name: 'Sigiriya Rock Fortress',
      country: 'Sri Lanka',
      image: '/bg_sigiriya.png',
      badge: 'UNESCO Heritage',
      tag: 'Ancient Citadel',
      desc: 'Climb the 5th-century rock fortress. See nearby sights in AR, ask Neva about its history and plan the day with Odyssey.',
      arEnabled: true
    },
    {
      name: 'Eiffel Tower & Seine',
      country: 'Paris, France',
      image: '/bg_eiffel_tower.png',
      badge: 'Iconic Wonder',
      tag: 'Architectural Marvel',
      desc: "Find viewpoints and cafés around the Champ de Mars, read travellers' stories and get walking directions on the 3D map.",
      arEnabled: true
    },
    {
      name: 'Colosseum & Roman Forum',
      country: 'Rome, Italy',
      image: '/bg_colosseum_rome.png',
      badge: 'Ancient Roman',
      tag: 'Gladiator Arena',
      desc: 'Plan a day in ancient Rome with Odyssey, ask Neva about the arena and find food and sights nearby.',
      arEnabled: true
    },
    {
      name: 'Great Wall of China',
      country: 'Beijing, China',
      image: '/bg_great_wall.png',
      badge: 'World Wonder',
      tag: 'Ancient Fortress',
      desc: 'Plan your trip from Beijing with Odyssey, compare stays and ask Neva which section of the wall to visit.',
      arEnabled: true
    },
    {
      name: 'Machu Picchu Citadel',
      country: 'Cusco, Peru',
      image: '/bg_machu_picchu.png',
      badge: 'Inca Wonder',
      tag: 'Sacred Valley',
      desc: 'Plan the journey through Cusco and the Sacred Valley, with flights, stays, visa guidance and a day-by-day itinerary.',
      arEnabled: true
    },
    {
      name: 'Pyramids of Giza & Sphinx',
      country: 'Cairo, Egypt',
      image: '/bg_pyramids_giza.png',
      badge: 'Ancient Wonder',
      tag: 'Pharaoh Tombs',
      desc: 'Plan your days in Cairo with Odyssey, ask Neva about the pyramids and the Sphinx, and find food and sights nearby.',
      arEnabled: true
    },
    {
      name: 'Taj Mahal Monument',
      country: 'Agra, India',
      image: '/bg_taj_mahal.png',
      badge: 'Mughal Architecture',
      tag: 'Marble Wonder',
      desc: 'Plan a visit to Agra, ask Neva about the best time to go and find food and sights near the monument.',
      arEnabled: true
    },
    {
      name: 'Statue of Liberty',
      country: 'New York, USA',
      image: '/bg_statue_liberty.png',
      badge: 'Historic Harbor',
      tag: 'Freedom Icon',
      desc: 'Plan New York day by day, find nearby places in Discover and get directions on the 3D map.',
      arEnabled: true
    },
    {
      name: 'Sydney Opera House',
      country: 'Sydney, Australia',
      image: '/bg_sydney_opera.png',
      badge: 'Modern Wonder',
      tag: 'Harbor Landmark',
      desc: "See harbour sights in AR, read travellers' stories and ask Neva what to do next.",
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
              Plan trips day by day with Odyssey, see what's around you in AR, follow city guides and chat with Neva, your AI travel companion.
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

              <NavLink 
                to="/app" 
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
              </NavLink>
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
                Everything around you, from hidden cafés and scenic viewpoints to authentic food, culture and local experiences.
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
                Simply raise your phone to see nearby attractions, food, shopping and hotels over the camera view.
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
              From planning your trip to finding your way on the ground and sharing your stories, here is how the app guides your adventure every step of the way.
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
                  maxWidth: '185px',
                  width: '100%',
                  borderRadius: '24px',
                  overflow: 'hidden',
                  boxShadow: '0 16px 40px -10px rgba(10, 17, 24, 0.28), 0 0 20px rgba(0, 122, 124, 0.15)',
                  border: '6px solid #111a24',
                  background: '#111a24'
                }}>
                  <AppScreen
                    module={appWorkflow[activeStep]}
                    imgStyle={{ maxHeight: '400px', objectFit: 'contain' }}
                    minHeight={400}
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
              14 Features, <span className="text-gradient-teal">One Unified Experience</span>
            </h2>
            <p style={{ fontSize: '1.08rem', color: 'var(--text-secondary)', margin: 0, lineHeight: 1.7 }}>
              Tap any feature below to see its screen and what it does.
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
                maxWidth: '250px',
                width: '100%',
                borderRadius: '28px',
                overflow: 'hidden',
                boxShadow: '0 24px 55px -12px rgba(10, 17, 24, 0.35), 0 0 30px rgba(0, 122, 124, 0.18)',
                border: '6px solid #111a24',
                background: '#111a24'
              }}>
                <AppScreen module={appScreens[activeScreenIndex]} />
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
                World <span className="text-gradient-teal">Travel Stories</span>
              </h2>
            </div>
            
            <NavLink to="/app" className="btn-glass">
              <span>Explore More...</span>
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
              Booking links to trusted travel partners
            </span>
          </div>

          <div className="partner-logos-row" style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', gap: '36px', flexWrap: 'wrap', opacity: 0.85 }}>
            <img src="/booking.svg" alt="Booking.com" style={{ height: '18px', objectFit: 'contain' }} onError={(e) => { e.currentTarget.style.display = 'none'; }} />
            <img src="/viator.png" alt="Viator" style={{ height: '24px', objectFit: 'contain' }} onError={(e) => { e.currentTarget.style.display = 'none'; }} />
            <img src="/getyourguide.png" alt="GetYourGuide" style={{ height: '28px', objectFit: 'contain' }} onError={(e) => { e.currentTarget.style.display = 'none'; }} />
            <img src="/skyscanner.png" alt="Skyscanner" style={{ height: '24px', objectFit: 'contain' }} onError={(e) => { e.currentTarget.style.display = 'none'; }} />
            <img src="/uber_logo.png" alt="Uber" style={{ height: '22px', objectFit: 'contain' }} onError={(e) => { e.currentTarget.style.display = 'none'; }} />
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
                  Neva knows where you are and answers like a local friend. Ask by text or voice, and get short answers with places you can open on a map.
                </p>

                {/* Sample Prompt Chips */}
                <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', marginBottom: '32px' }}>
                  {[
                    '“Find me the best authentic seafood street spot within 10 mins walk”',
                    '“Explain the architectural background and history of this landmark”',
                    '“It started raining. What indoor places are near me?”',
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
                  Available on iOS and Android. Download the nexARound app today and explore destinations around the world.
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
