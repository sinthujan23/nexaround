import React, { useState } from 'react';

const API_BASE = 'https://api.nexaround.com/api/v1';

export async function apiFetch(endpoint, options = {}) {
  const token = localStorage.getItem('admin_token');
  const headers = {
    'Content-Type': 'application/json',
    ...(token ? { 'Authorization': `Bearer ${token}` } : {}),
    ...options.headers,
  };

  const response = await fetch(`${API_BASE}${endpoint}`, {
    ...options,
    headers,
  });

  if (!response.ok) {
    let errorMsg = response.statusText;
    try {
      const errData = await response.json();
      if (errData && errData.detail) {
        errorMsg = typeof errData.detail === 'string' ? errData.detail : JSON.stringify(errData.detail);
      }
    } catch {
      // Ignore error parsing
    }
    throw new Error(errorMsg || `Request failed with status ${response.status}`);
  }

  if (response.status === 204) {
    return null;
  }

  return response.json();
}

export async function apiGet(endpoint) {
  return apiFetch(endpoint, { method: 'GET' });
}

export async function apiPost(endpoint, body) {
  return apiFetch(endpoint, {
    method: 'POST',
    body: body ? JSON.stringify(body) : undefined,
  });
}

export async function apiPut(endpoint, body) {
  return apiFetch(endpoint, {
    method: 'PUT',
    body: body ? JSON.stringify(body) : undefined,
  });
}

export async function apiDelete(endpoint) {
  return apiFetch(endpoint, { method: 'DELETE' });
}

export function useApi(endpoint, options = {}) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [refreshTrigger, setRefreshTrigger] = useState(0);

  const [prevEndpoint, setPrevEndpoint] = useState(endpoint);
  const [prevTrigger, setPrevTrigger] = useState(refreshTrigger);

  if (endpoint !== prevEndpoint || refreshTrigger !== prevTrigger) {
    setPrevEndpoint(endpoint);
    setPrevTrigger(refreshTrigger);
    setLoading(true);
  }

  const refetch = () => setRefreshTrigger(prev => prev + 1);

  React.useEffect(() => {
    let active = true;
    apiFetch(endpoint, options)
      .then(res => {
        if (active) {
          setData(res);
          setError(null);
        }
      })
      .catch(err => {
        if (active) {
          setError(err.message || 'An error occurred');
        }
      })
      .finally(() => {
        if (active) {
          setLoading(false);
        }
      });

    return () => {
      active = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [endpoint, refreshTrigger]);

  return { data, loading, error, refetch };
}

export { API_BASE };
