import { BrowserRouter, Routes, Route, useLocation, Navigate } from 'react-router-dom';
import { useEffect } from 'react';
import Navbar from './components/Navbar';
import Footer from './components/Footer';
import ScrollToTopButton from './components/ScrollToTopButton';

import Home from './pages/Home';
import Services from './pages/Services';
import Solutions from './pages/Solutions';
import NexARoundApp from './pages/NexARoundApp';
import About from './pages/About';
import GetApp from './pages/GetApp';
import Privacy from './pages/Privacy';
import Terms from './pages/Terms';

function ScrollToTopOnNavigate() {
  const { pathname, hash } = useLocation();
  
  useEffect(() => {
    if (hash) {
      setTimeout(() => {
        const elem = document.querySelector(hash);
        if (elem) {
          elem.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
      }, 100);
      return;
    }
    window.scrollTo(0, 0);
  }, [pathname, hash]);

  return null;
}

export default function App() {
  return (
    <BrowserRouter>
      <ScrollToTopOnNavigate />
      <div style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', background: 'var(--bg-white)', position: 'relative' }}>
        <Navbar />
        <main style={{ flex: 1, paddingTop: '0px' }}>
          <Routes>
            <Route path="/" element={<Home />} />
            <Route path="/services" element={<Services />} />
            <Route path="/solutions" element={<Solutions />} />
            <Route path="/app" element={<NexARoundApp />} />
            <Route path="/about" element={<About />} />
            <Route path="/contact" element={<Navigate to="/" replace />} />
            <Route path="/get-app" element={<GetApp />} />
            <Route path="/download" element={<GetApp />} />
            <Route path="/privacy" element={<Privacy />} />
            <Route path="/terms" element={<Terms />} />
          </Routes>
        </main>
        <Footer />
        <ScrollToTopButton />
      </div>
    </BrowserRouter>
  );
}
