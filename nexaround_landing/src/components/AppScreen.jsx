// A phone screenshot of an app feature, or a holding panel when the feature
// has no screenshot yet.
export default function AppScreen({ module, imgStyle, minHeight = 420 }) {
  if (module.image) {
    return (
      <img
        src={module.image}
        alt={module.title}
        style={{ width: '100%', height: 'auto', display: 'block', ...imgStyle }}
      />
    );
  }
  const Icon = module.icon;
  return (
    <div
      role="img"
      aria-label={module.title}
      style={{
        minHeight,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        gap: '12px',
        padding: '32px 22px',
        textAlign: 'center',
        color: '#ffffff',
        background: 'linear-gradient(160deg, #007A7C 0%, #0B3B45 100%)',
      }}
    >
      {Icon && <Icon style={{ width: '52px', height: '52px' }} strokeWidth={1.5} aria-hidden="true" />}
      <strong style={{ fontSize: '1.15rem', fontWeight: 600 }}>{module.title}</strong>
      <span style={{ fontSize: '0.88rem', lineHeight: 1.5, color: 'rgba(255, 255, 255, 0.82)' }}>{module.short}</span>
    </div>
  );
}
