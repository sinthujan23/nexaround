import React from 'react';

export default class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error) {
    return { hasError: true, error };
  }

  componentDidCatch(error, errorInfo) {
    console.error('ErrorBoundary caught an error:', error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div style={{
          padding: '40px 24px',
          textAlign: 'center',
          maxWidth: '560px',
          margin: '60px auto',
          background: 'var(--bg-card, #ffffff)',
          borderRadius: '16px',
          border: '1px solid var(--border, #e5e7eb)',
          boxShadow: '0 4px 20px rgba(0,0,0,0.06)'
        }}>
          <div style={{
            width: '56px',
            height: '56px',
            borderRadius: '50%',
            background: 'rgba(229, 57, 53, 0.1)',
            color: 'var(--danger, #e53935)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            margin: '0 auto 16px auto',
            fontSize: '24px'
          }}>
            ⚠️
          </div>
          <h2 style={{ fontSize: '18px', fontWeight: 700, margin: '0 0 8px 0', color: 'var(--text-primary, #111827)' }}>
            Something went wrong loading this section
          </h2>
          <p style={{ fontSize: '13px', color: 'var(--text-secondary, #6b7280)', marginBottom: '20px', lineHeight: 1.5 }}>
            {this.state.error?.message || 'An unexpected rendering error occurred.'}
          </p>
          <button
            onClick={() => {
              this.setState({ hasError: false, error: null });
              window.location.reload();
            }}
            className="btn btn-primary"
            style={{ padding: '8px 20px', fontSize: '13px' }}
          >
            Reload Page
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
