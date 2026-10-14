import React from 'react';
import { PageError } from './Kit';

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
        <PageError
          error={this.state.error}
          title="Section Render Error"
          onRetry={() => {
            this.setState({ hasError: false, error: null });
            window.location.reload();
          }}
        >
          {this.state.error?.message || 'An unexpected rendering error occurred.'}
        </PageError>
      );
    }
    return this.props.children;
  }
}
