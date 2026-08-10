(function() {
  "use strict";

  function getCurrentPath() {
    var path = window.location.pathname || '';
    var filename = path.substring(path.lastIndexOf('/') + 1);
    if (!filename || filename === 'index.html' || filename === 'index') {
      return '/';
    }
    return '/' + filename.replace(/\.html$/, '');
  }

  function renderComponents() {
    var path = getCurrentPath();

    // 1. Render Header Nav
    var siteNav = document.getElementById('siteNav');
    if (siteNav) {
      if (path === '/contact') {
        siteNav.classList.remove('nav--onDark');
      }

      function navAttr(target) {
        return (path === target) ? ' aria-current="page"' : '';
      }

      siteNav.innerHTML =
        '<div class="nav__inner">' +
          '<button class="nav__burger" id="navBurger" aria-label="Open menu"><i></i><i></i><i></i></button>' +
          '<a href="/" class="nav__logo" aria-label="NexARound Technologies home">' +
            '<span class="nav__logo-badge"><img src="tech_logo_v3.png" alt="nexARound Technologies" class="nav__logo-img"></span>' +
            '<span class="nav__logo-text"><span class="nav__logo-main">nex<b>AR</b>ound</span><span class="nav__logo-sub">Technologies</span></span>' +
          '</a>' +
          '<nav class="nav__pill" aria-label="Primary">' +
            '<a href="/app"' + navAttr('/app') + '>nexARound App</a>' +
            '<a href="/services"' + navAttr('/services') + '>Services</a>' +
            '<a href="/offerings"' + navAttr('/offerings') + '>Offerings</a>' +
            '<a href="/ai-data"' + navAttr('/ai-data') + '>AI, ML &amp; Data</a>' +
            '<a href="/blockchain"' + navAttr('/blockchain') + '>Blockchain</a>' +
            '<a href="/about"' + navAttr('/about') + '>About Us</a>' +
            '<a href="/case-studies"' + navAttr('/case-studies') + '>Case Studies</a>' +
            '<a href="/industries"' + navAttr('/industries') + '>Industries</a>' +
          '</nav>' +
          '<a href="/contact" class="nav__ai"' + navAttr('/contact') + '>' +
            '<svg width="15" height="15" viewBox="0 0 16 16" fill="currentColor"><path d="M8 1L9.5 6.5L15 8L9.5 9.5L8 15L6.5 9.5L1 8L6.5 6.5L8 1Z"/></svg>' +
            ' Let\'s Talk' +
          '</a>' +
        '</div>';
    }

    // 2. Render Mega Menu
    var mega = document.getElementById('mega');
    if (mega) {
      function megaClass(target) {
        return (path === target) ? ' class="is-active"' : '';
      }

      mega.innerHTML =
        '<div class="mega__left">' +
          '<button class="mega__close" id="megaClose" aria-label="Close menu">&#10005;</button>' +
          '<nav class="mega__nav" aria-label="All pages">' +
            '<a href="/"' + megaClass('/') + '>Home</a>' +
            '<a href="/app"' + megaClass('/app') + '>nexARound App</a>' +
            '<a href="/services"' + megaClass('/services') + '>Services</a>' +
            '<a href="/offerings"' + megaClass('/offerings') + '>Offerings</a>' +
            '<a href="/ai-data"' + megaClass('/ai-data') + '>AI, ML &amp; Data</a>' +
            '<a href="/blockchain"' + megaClass('/blockchain') + '>Blockchain</a>' +
            '<a href="/about"' + megaClass('/about') + '>About Us</a>' +
            '<a href="/case-studies"' + megaClass('/case-studies') + '>Case Studies</a>' +
            '<a href="/industries"' + megaClass('/industries') + '>Industries</a>' +
          '</nav>' +
          '<div class="mega__sub">' +
            '<a href="/technology">Technology Expertise</a>' +
            '<a href="/about#process">Engagement Process</a>' +
            '<a href="/about#models">Engagement Models</a>' +
          '</div>' +
          '<div class="mega__social"><span>in</span><span>&#10005;</span><span>f</span><span>&#9654;</span></div>' +
        '</div>' +
        '<div class="mega__right">' +
          '<h2>Full-stack engineering to fast-track your growth</h2>' +
          '<div class="mega__cards">' +
            '<a href="/erp" class="mega__card art art--1"><h3>Enterprise Management Software</h3><span class="rm">Know More <svg width="13" height="13" viewBox="0 0 14 14" fill="none"><path d="M3 11L11 3M11 3H4.5M11 3V9.5" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg></span></a>' +
            '<a href="/app" class="mega__card art art--4"><h3>The nexARound App</h3><span class="rm">Know More <svg width="13" height="13" viewBox="0 0 14 14" fill="none"><path d="M3 11L11 3M11 3H4.5M11 3V9.5" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg></span></a>' +
          '</div>' +
        '</div>';
    }

    // 3. Render Footer if #siteFooter exists
    var siteFooter = document.getElementById('siteFooter');
    if (siteFooter) {
      var yr = new Date().getFullYear();
      siteFooter.innerHTML =
        '<div class="footer__cols">' +
          '<div class="footer__col">' +
            '<h4>Services</h4>' +
            '<a href="/services">Digital Transformation</a>' +
            '<a href="/services">Software Engineering</a>' +
            '<a href="/services">Cloud Implementation</a>' +
            '<a href="/services">UI / UX Design</a>' +
            '<a href="/services">Quality &amp; Automation</a>' +
          '</div>' +
          '<div class="footer__col">' +
            '<h4>Products &amp; Solutions</h4>' +
            '<a href="/app">nexARound App</a>' +
            '<a href="/erp">ERP &amp; Business Solutions</a>' +
            '<a href="/ai-data">AI, ML &amp; Data Solutions</a>' +
            '<a href="/blockchain">Blockchain</a>' +
            '<a href="/technology">Technology Expertise</a>' +
          '</div>' +
          '<div class="footer__col">' +
            '<h4>Company</h4>' +
            '<a href="/about">About Us</a>' +
            '<a href="/industries">Industries We Serve</a>' +
            '<a href="/about#process">Engagement Process</a>' +
            '<a href="/about#models">Engagement Models</a>' +
            '<a href="/about#why">Why Partner With Us</a>' +
          '</div>' +
          '<div class="footer__col">' +
            '<h4>Support</h4>' +
            '<a href="mailto:support@nexaround.com">support@nexaround.com</a>' +
            '<a href="#">Privacy Statement</a>' +
            '<a href="#">Terms of Use</a>' +
          '</div>' +
        '</div>' +
        '<div class="footer__brand">' +
          '<p>&copy; ' + yr + ' NexARound Technologies. Full-stack engineering to fast-track your growth.</p>' +
          '<div class="footer__social">' +
            '<a href="#" aria-label="LinkedIn">in</a>' +
            '<a href="#" aria-label="X">&#10005;</a>' +
            '<a href="#" aria-label="Facebook">f</a>' +
            '<a href="#" aria-label="YouTube">&#9654;</a>' +
          '</div>' +
        '</div>';
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', renderComponents);
  } else {
    renderComponents();
  }
})();
