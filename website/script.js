(function(){
  "use strict";

  document.querySelectorAll('[data-year]').forEach(function(el){
    el.textContent = new Date().getFullYear();
  });

  /* ---------- Tabbed Capabilities Filter ---------- */
  document.querySelectorAll('.cap-tab').forEach(function(tab){
    tab.addEventListener('click', function(){
      document.querySelectorAll('.cap-tab').forEach(function(t){ t.classList.remove('is-active'); });
      tab.classList.add('is-active');
      var filter = tab.getAttribute('data-filter');
      document.querySelectorAll('.cap-card').forEach(function(card){
        if(filter === 'all' || card.getAttribute('data-category') === filter){
          card.classList.remove('is-hidden');
        } else {
          card.classList.add('is-hidden');
        }
      });
    });
  });

  /* ---------- Nav scroll state ---------- */
  var nav = document.getElementById('siteNav');
  var toTop = document.getElementById('toTop');
  function onScroll(){
    var y = window.scrollY || document.documentElement.scrollTop;
    if(nav) nav.classList.toggle('is-scrolled', y > 30);
    if(toTop) toTop.classList.toggle('is-shown', y > 500);
  }
  window.addEventListener('scroll', onScroll, {passive:true});
  onScroll();

  if(toTop){
    toTop.addEventListener('click', function(){
      window.scrollTo({top:0, behavior:'smooth'});
    });
  }

  /* ---------- Mega menu ---------- */
  var burger = document.getElementById('navBurger');
  var mega = document.getElementById('mega');
  var megaClose = document.getElementById('megaClose');

  function openMega(){
    if(!mega) return;
    mega.classList.add('is-open');
    document.body.style.overflow = 'hidden';
    if(megaClose) megaClose.focus();
  }
  function closeMega(){
    if(!mega) return;
    mega.classList.remove('is-open');
    document.body.style.overflow = '';
    if(burger) burger.focus();
  }
  if(burger) burger.addEventListener('click', openMega);
  if(megaClose) megaClose.addEventListener('click', closeMega);
  document.addEventListener('keydown', function(e){
    if(e.key === 'Escape' && mega && mega.classList.contains('is-open')) closeMega();
  });

  /* ---------- Reveal on scroll ---------- */
  var rv = document.querySelectorAll('.rv');
  if('IntersectionObserver' in window){
    var io = new IntersectionObserver(function(entries){
      entries.forEach(function(en){
        if(en.isIntersecting){ en.target.classList.add('is-in'); io.unobserve(en.target); }
      });
    }, {threshold:0.12, rootMargin:'0px 0px -50px 0px'});
    rv.forEach(function(el){ io.observe(el); });
  } else {
    rv.forEach(function(el){ el.classList.add('is-in'); });
  }

  /* ---------- Counters ---------- */
  var nums = document.querySelectorAll('[data-count]');
  function count(el){
    var target = parseFloat(el.getAttribute('data-count')) || 0;
    var suffix = el.getAttribute('data-suffix') || '';
    var prefix = el.getAttribute('data-prefix') || '';
    var dur = 1500, start = null;
    function step(ts){
      if(start === null) start = ts;
      var p = Math.min((ts - start) / dur, 1);
      var e = 1 - Math.pow(1 - p, 3);
      el.textContent = prefix + Math.floor(e * target).toLocaleString() + suffix;
      if(p < 1) requestAnimationFrame(step);
      else el.textContent = prefix + target.toLocaleString() + suffix;
    }
    requestAnimationFrame(step);
  }
  if('IntersectionObserver' in window && nums.length){
    var nio = new IntersectionObserver(function(entries){
      entries.forEach(function(en){
        if(en.isIntersecting){ count(en.target); nio.unobserve(en.target); }
      });
    }, {threshold:0.4});
    nums.forEach(function(el){ nio.observe(el); });
  }

  /* ---------- Hero slide bars ---------- */
  var bars = document.querySelectorAll('.hero__bars i');
  if(bars.length > 1){
    var bi = 0;
    setInterval(function(){
      bars.forEach(function(b){ b.classList.remove('is-active'); });
      bi = (bi + 1) % bars.length;
      bars[bi].classList.add('is-active');
    }, 6000);
  }

  /* ---------- Video placeholder feedback ---------- */
  document.querySelectorAll('.video-block__play').forEach(function(btn){
    btn.addEventListener('click', function(){
      var cap = btn.parentElement.querySelector('.video-block__cap');
      if(!cap) return;
      var orig = cap.textContent;
      cap.textContent = 'Drop your video file in here';
      setTimeout(function(){ cap.textContent = orig; }, 2200);
    });
  });


  /* ---------- App screen carousel ---------- */
  document.querySelectorAll('[data-appdeck]').forEach(function(deck){
    var phones = deck.querySelectorAll('.phone');
    var host = deck.closest('[data-appshow]') || document;
    var tabs = host.querySelectorAll('.apptab');
    var cur = 0, timer = null;

    function show(i){
      cur = i;
      phones.forEach(function(p, n){ p.classList.toggle('is-active', n === i); });
      tabs.forEach(function(t, n){ t.classList.toggle('is-active', n === i); });
    }
    function start(){ stop(); timer = setInterval(function(){ show((cur + 1) % phones.length); }, 4200); }
    function stop(){ if(timer) clearInterval(timer); }

    tabs.forEach(function(t){
      t.addEventListener('click', function(){
        show(parseInt(t.getAttribute('data-i'), 10)); start();
      });
    });
    if(host.addEventListener){
      host.addEventListener('mouseenter', stop);
      host.addEventListener('mouseleave', start);
    }
    if(phones.length) start();
  });

  /* ---------- Contact form ---------- */
  var form = document.getElementById('contactForm');
  if(form){
    form.addEventListener('submit', function(e){
      e.preventDefault();
      var s = form.querySelector('.form__status');
      if(s) s.hidden = false;
    });
  }
})();

/* ---------- App screen carousel ---------- */
(function(){
  document.querySelectorAll('[data-appshow]').forEach(function(box){
    var phones = box.querySelectorAll('.phone');
    var btns = box.querySelectorAll('.apbtn');
    var section = box.closest('section') || document;
    var cur = 0, timer = null;

    function show(i){
      cur = i;
      phones.forEach(function(p,n){ p.classList.toggle('is-on', n===i); });
      btns.forEach(function(b,n){ b.classList.toggle('is-on', n===i); });
      
      var bgs = section.querySelectorAll('.appshow__bg');
      bgs.forEach(function(bg,n){
        if(n === i){
          bg.classList.add('is-on');
          bg.style.opacity = '1';
          bg.style.zIndex = '2';
        } else {
          bg.classList.remove('is-on');
          bg.style.opacity = '0';
          bg.style.zIndex = '1';
        }
      });
    }
    function play(){ stop(); timer = setInterval(function(){ show((cur+1)%phones.length); }, 4500); }
    function stop(){ if(timer) clearInterval(timer); }

    if(phones.length && btns.length){
      btns.forEach(function(b, idx){
        var i = parseInt(b.getAttribute('data-i'), 10);
        if(isNaN(i)) i = idx;
        
        b.addEventListener('mouseenter', function(){
          if (window.matchMedia && window.matchMedia('(hover: hover)').matches) {
            stop();
            show(i);
          }
        });

        function handleSelect(e, targetIdx) {
          if (e) {
            e.preventDefault();
            e.stopPropagation();
          }
          stop();
          show(targetIdx);
          play();
          if (b.blur) b.blur();

          if (window.innerWidth <= 900) {
            var stage = box.querySelector('.appshow__stage');
            if (stage) {
              stage.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
          }
        }

        b.addEventListener('click', function(e){ handleSelect(e, i); });
        b.addEventListener('touchend', function(e){ handleSelect(e, i); });
      });
      box.addEventListener('mouseleave', play);
      show(0);
      play();
    }
  });
})();

// YouTube API auto-trigger for seamless background video loop
(function(){
  function initYTPlayer(iframeId) {
    var iframe = document.getElementById(iframeId);
    if (!iframe) return;
    var cover = iframe.parentElement.querySelector('.hero__yt-cover');
    new YT.Player(iframeId, {
      playerVars: {
        autoplay: 1,
        controls: 0,
        showinfo: 0,
        rel: 0,
        modestbranding: 1,
        loop: 1,
        fs: 0,
        cc_load_policy: 0,
        iv_load_policy: 3,
        autohide: 1,
        disablekb: 1,
        playsinline: 1
      },
      events: {
        onReady: function(event) {
          event.target.mute();
          event.target.playVideo();
        },
        onStateChange: function(event) {
          if (event.data === YT.PlayerState.PLAYING) {
            if (cover) cover.classList.add('is-playing');
          }
          if (event.data === YT.PlayerState.ENDED) {
            if (cover) cover.classList.remove('is-playing');
            event.target.seekTo(0);
            event.target.playVideo();
          }
          if (event.data === YT.PlayerState.PAUSED) {
            event.target.playVideo();
          }
        }
      }
    });
  }

  if (document.getElementById('ytHeroPlayer') || document.getElementById('ytAppHeroPlayer')) {
    window.onYouTubeIframeAPIReady = function() {
      initYTPlayer('ytHeroPlayer');
      initYTPlayer('ytAppHeroPlayer');
    };
    if (!window.YT) {
      var tag = document.createElement('script');
      tag.src = "https://www.youtube.com/iframe_api";
      var firstScriptTag = document.getElementsByTagName('script')[0];
      if (firstScriptTag && firstScriptTag.parentNode) {
        firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);
      } else {
        document.head.appendChild(tag);
      }
    } else if (window.YT && window.YT.Player) {
      initYTPlayer('ytHeroPlayer');
      initYTPlayer('ytAppHeroPlayer');
    }
  }
})();

