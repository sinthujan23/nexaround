import { useState, useEffect, useCallback } from 'react';
import { WifiOffIcon, RefreshIcon, CheckCircleIcon } from './Icons';

export default function NetworkStatusBar() {
  const [isOnline, setIsOnline] = useState(
    typeof navigator !== 'undefined' ? navigator.onLine : true
  );
  const [wasOffline, setWasOffline] = useState(false);
  const [showRestored, setShowRestored] = useState(false);
  const [serverReachable, setServerReachable] = useState(true);
  const [isChecking, setIsChecking] = useState(false);

  // Connectivity check function
  const checkConnectivity = useCallback(async () => {
    setIsChecking(true);
    try {
      // Test navigator first
      if (typeof navigator !== 'undefined' && !navigator.onLine) {
        setIsOnline(false);
        setIsChecking(false);
        return false;
      }

      // Quick lightweight ping with timeout to ensure actual internet/server reachability
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 4000);
      
      try {
        // Fetch health or favicon with cache-buster
        const res = await fetch(`https://api.nexaround.com/api/v1/health?_t=${Date.now()}`, {
          method: 'GET',
          signal: controller.signal,
          cache: 'no-store'
        });
        clearTimeout(timeoutId);
        
        setIsOnline(true);
        setServerReachable(true);
        
        if (!isOnline || !serverReachable || wasOffline) {
          setShowRestored(true);
          setWasOffline(false);
          window.dispatchEvent(new CustomEvent('network:reconnected'));
          setTimeout(() => setShowRestored(false), 3500);
        }
        return true;
      } catch (err) {
        clearTimeout(timeoutId);
        // If aborted or network failed
        if (err.name === 'AbortError' || /failed to fetch|network/i.test(err.message)) {
          // If navigator says offline, it's total offline; otherwise server unreachable
          if (!navigator.onLine) {
            setIsOnline(false);
          } else {
            setServerReachable(false);
          }
          setWasOffline(true);
          return false;
        }
        // If server returned some HTTP response (even 404), network is actually alive!
        setIsOnline(true);
        setServerReachable(true);
        if (wasOffline) {
          setShowRestored(true);
          setWasOffline(false);
          window.dispatchEvent(new CustomEvent('network:reconnected'));
          setTimeout(() => setShowRestored(false), 3500);
        }
        return true;
      }
    } finally {
      setIsChecking(false);
    }
  }, [isOnline, serverReachable, wasOffline]);

  useEffect(() => {
    const handleOnlineEvent = () => {
      setIsOnline(true);
      setShowRestored(true);
      setWasOffline(false);
      setServerReachable(true);
      window.dispatchEvent(new CustomEvent('network:reconnected'));
      setTimeout(() => setShowRestored(false), 3500);
    };

    const handleOfflineEvent = () => {
      setIsOnline(false);
      setWasOffline(true);
      setShowRestored(false);
    };

    const handleFetchError = (e) => {
      if (e.detail?.isOffline || !navigator.onLine) {
        setIsOnline(false);
        setWasOffline(true);
      } else {
        setServerReachable(false);
        setWasOffline(true);
      }
    };

    const handleFetchSuccess = () => {
      if (!serverReachable || !isOnline) {
        setIsOnline(true);
        setServerReachable(true);
        if (wasOffline) {
          setShowRestored(true);
          setWasOffline(false);
          setTimeout(() => setShowRestored(false), 3500);
        }
      }
    };

    window.addEventListener('online', handleOnlineEvent);
    window.addEventListener('offline', handleOfflineEvent);
    window.addEventListener('network:fetch-error', handleFetchError);
    window.addEventListener('network:fetch-success', handleFetchSuccess);

    return () => {
      window.removeEventListener('online', handleOnlineEvent);
      window.removeEventListener('offline', handleOfflineEvent);
      window.removeEventListener('network:fetch-error', handleFetchError);
      window.removeEventListener('network:fetch-success', handleFetchSuccess);
    };
  }, [serverReachable, isOnline, wasOffline]);

  const isDisconnected = !isOnline || !serverReachable;

  if (!isDisconnected && !showRestored) {
    return null;
  }

  if (showRestored) {
    return (
      <aside aria-label="Network status" className="network-status-bar network-bar-restored" role="status">
        <div className="network-bar-content">
          <span className="network-status-dot dot-green" />
          <CheckCircleIcon size={16} />
          <span className="network-bar-text">
            <strong>Back online</strong> — Connection restored. Data refreshed.
          </span>
        </div>
      </aside>
    );
  }

  return (
    <aside aria-label="Network alert" className="network-status-bar network-bar-offline" role="alert">
      <div className="network-bar-content">
        <span className="network-status-dot dot-pulse" />
        <WifiOffIcon size={17} />
        <div className="network-bar-text-group">
          <span className="network-bar-title">
            {!isOnline ? "You're currently offline" : 'Connection to server lost'}
          </span>
          <span className="network-bar-subtitle">
            {!isOnline
              ? 'Check your internet connection. Changes will sync once reconnected.'
              : 'Unable to reach nexAround API. Reconnecting automatically...'}
          </span>
        </div>
      </div>
      <div className="network-bar-actions">
        <button
          type="button"
          className="network-bar-retry-btn"
          onClick={checkConnectivity}
          disabled={isChecking}
        >
          <RefreshIcon size={14} className={isChecking ? 'spin-anim' : ''} />
          <span>{isChecking ? 'Checking...' : 'Retry Connection'}</span>
        </button>
      </div>
    </aside>
  );
}
