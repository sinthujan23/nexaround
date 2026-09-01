import React from 'react';

export default function StoreButtons({ 
  theme = 'dark',        // 'dark' (black pill for light bg), 'light' (white pill), 'glass'/'onDark' (for dark footer/hero)
  direction = 'row',     // 'row' or 'column'
  align = 'center',      // 'center', 'flex-start', 'flex-end'
  showRating = false 
}) {
  const isOnDark = theme === 'onDark' || theme === 'glass';
  const isLight = theme === 'light';

  // Button styles based on theme
  const getButtonBg = () => {
    if (isOnDark) return 'rgba(255, 255, 255, 0.08)';
    if (isLight) return '#ffffff';
    return '#000000'; // solid black pill for light containers (like Ziggo reference)
  };

  const getButtonBorder = () => {
    if (isOnDark) return '1px solid rgba(255, 255, 255, 0.25)';
    if (isLight) return '1px solid #e2e8f0';
    return '1px solid #1a1a1a';
  };

  const getTextColor = () => {
    if (isLight) return '#000000';
    return '#ffffff';
  };

  const getSubtextColor = () => {
    if (isLight) return '#64748b';
    return 'rgba(255, 255, 255, 0.7)';
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: align, gap: '14px' }}>
      {/* Store Badges Container */}
      <div 
        className="store-buttons-container"
        style={{ 
          display: 'flex', 
          flexDirection: direction === 'column' ? 'column' : 'row',
          gap: '12px', 
          alignItems: align === 'flex-start' ? 'flex-start' : 'center', 
          justifyContent: align,
          flexWrap: 'wrap' 
        }}
      >
        
        {/* Google Play Button */}
        <a
          href="/get-app"
          className="store-button-item"
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: '12px',
            background: getButtonBg(),
            color: getTextColor(),
            border: getButtonBorder(),
            borderRadius: '12px',
            padding: '10px 18px',
            textDecoration: 'none',
            boxShadow: isOnDark 
              ? '0 4px 16px rgba(0,0,0,0.3), inset 0 1px 0 rgba(255,255,255,0.1)' 
              : '0 4px 16px rgba(0,0,0,0.25)',
            backdropFilter: isOnDark ? 'blur(10px)' : 'none',
            WebkitBackdropFilter: isOnDark ? 'blur(10px)' : 'none',
            transition: 'all 0.25s cubic-bezier(0.16, 1, 0.3, 1)',
            cursor: 'pointer'
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.transform = 'translateY(-2px)';
            e.currentTarget.style.borderColor = '#00d2d3';
            e.currentTarget.style.boxShadow = isOnDark 
              ? '0 8px 25px rgba(0, 210, 211, 0.25)' 
              : '0 8px 25px rgba(0,0,0,0.45)';
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.transform = 'translateY(0)';
            e.currentTarget.style.borderColor = getButtonBorder().split(' ')[2];
            e.currentTarget.style.boxShadow = isOnDark 
              ? '0 4px 16px rgba(0,0,0,0.3), inset 0 1px 0 rgba(255,255,255,0.1)' 
              : '0 4px 16px rgba(0,0,0,0.25)';
          }}
        >
          {/* Official Google Play Triangle SVG */}
          <svg style={{ width: '22px', height: '22px', flexShrink: 0 }} viewBox="0 0 24 24" fill="none">
            <path d="M3.609 1.814L13.793 12 3.61 22.186A2.22 2.22 0 0 1 3 20.617V3.383c0-.623.23-1.196.609-1.569z" fill="#00C1A6"/>
            <path d="M17.18 8.613L4.74 1.433C4.37 1.22 3.967 1.134 3.609 1.214l10.184 10.186 3.387-2.787z" fill="#FFD400"/>
            <path d="M3.609 22.786c.358.08.761-.006 1.131-.22l12.44-7.18-3.387-2.786L3.609 22.786z" fill="#FF3333"/>
            <path d="M21.05 10.84l-3.87-2.227-3.387 2.787 3.387 2.786 3.87-2.227a1.36 1.36 0 0 0 0-2.319z" fill="#0083D6"/>
          </svg>

          <div style={{ display: 'flex', flexDirection: 'column', textAlign: 'left', lineHeight: 1.15 }}>
            <span style={{ fontSize: '0.6rem', textTransform: 'uppercase', letterSpacing: '0.6px', color: getSubtextColor(), fontWeight: 500 }}>
              Get it on
            </span>
            <span style={{ fontSize: '1rem', fontWeight: 500, letterSpacing: '-0.02em' }}>
              Google Play
            </span>
          </div>
        </a>

        {/* Apple App Store Button */}
        <a
          href="/get-app"
          className="store-button-item"
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: '12px',
            background: getButtonBg(),
            color: getTextColor(),
            border: getButtonBorder(),
            borderRadius: '12px',
            padding: '10px 18px',
            textDecoration: 'none',
            boxShadow: isOnDark 
              ? '0 4px 16px rgba(0,0,0,0.3), inset 0 1px 0 rgba(255,255,255,0.1)' 
              : '0 4px 16px rgba(0,0,0,0.25)',
            backdropFilter: isOnDark ? 'blur(10px)' : 'none',
            WebkitBackdropFilter: isOnDark ? 'blur(10px)' : 'none',
            transition: 'all 0.25s cubic-bezier(0.16, 1, 0.3, 1)',
            cursor: 'pointer'
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.transform = 'translateY(-2px)';
            e.currentTarget.style.borderColor = '#00d2d3';
            e.currentTarget.style.boxShadow = isOnDark 
              ? '0 8px 25px rgba(0, 210, 211, 0.25)' 
              : '0 8px 25px rgba(0,0,0,0.45)';
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.transform = 'translateY(0)';
            e.currentTarget.style.borderColor = getButtonBorder().split(' ')[2];
            e.currentTarget.style.boxShadow = isOnDark 
              ? '0 4px 16px rgba(0,0,0,0.3), inset 0 1px 0 rgba(255,255,255,0.1)' 
              : '0 4px 16px rgba(0,0,0,0.25)';
          }}
        >
          {/* Apple Logo */}
          <svg width="22" height="22" viewBox="0 0 24 24" fill={isLight ? '#000000' : '#ffffff'}>
            <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M15.97 6.32c.67-.82 1.13-1.97.99-3.12-1 .04-2.18.67-2.88 1.49-.62.72-1.16 1.89-.99 3.02 1.11.09 2.22-.56 2.88-1.39z"/>
          </svg>
          <div style={{ display: 'flex', flexDirection: 'column', textAlign: 'left', lineHeight: 1.15 }}>
            <span style={{ fontSize: '0.6rem', textTransform: 'uppercase', letterSpacing: '0.6px', color: getSubtextColor(), fontWeight: 500 }}>
              Download on the
            </span>
            <span style={{ fontSize: '1rem', fontWeight: 500, letterSpacing: '-0.02em' }}>
              App Store
            </span>
          </div>
        </a>

      </div>
    </div>
  );
}
