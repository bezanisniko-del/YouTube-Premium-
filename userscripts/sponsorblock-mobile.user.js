// ==UserScript==
// @name         SponsorBlock Mobile
// @namespace    https://github.com/bezanisniko-del/YouTube-Premium-
// @version      1.0.0
// @description  Auto-skips sponsored segments, intros, outros and subscribe-begging on YouTube using the community SponsorBlock API. Built for iOS Safari via the free Userscripts app.
// @match        *://m.youtube.com/*
// @match        *://www.youtube.com/*
// @match        *://music.youtube.com/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

/*
 * Uses the public SponsorBlock API (https://sponsor.ajay.app) — the same
 * crowdsourced segment database the official browser extension uses.
 *
 * Privacy: video IDs are never sent in the clear. The script sends only the
 * first 4 characters of the SHA-256 hash of the video ID, so the server gets
 * back segments for a bucket of videos and cannot tell which one you watched.
 * This is the same hash-prefix scheme the official extension uses.
 */

(function () {
  'use strict';

  // ---------------------------------------------------------------------------
  // CONFIG — flip these to taste. true = skip it automatically.
  // ---------------------------------------------------------------------------
  const SKIP = {
    sponsor: true, // paid sponsor reads
    selfpromo: true, // "check out my merch / Patreon"
    interaction: true, // "smash that like button"
    intro: true, // title card / intro animation
    outro: true, // end cards, credits
    preview: false, // recap of what's coming up (off: often useful)
    music_offtopic: true, // non-music sections of music videos
    filler: false, // tangents and jokes (off: this is often the good part)
  };

  const SHOW_TOAST = true; // brief on-screen notice when something is skipped
  const API = 'https://sponsor.ajay.app';

  const LABEL = {
    sponsor: 'sponsor',
    selfpromo: 'self-promo',
    interaction: 'subscribe reminder',
    intro: 'intro',
    outro: 'outro',
    preview: 'preview',
    music_offtopic: 'non-music section',
    filler: 'filler',
  };

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------
  let currentVideoId = null;
  let segments = [];
  const handled = new Set(); // UUIDs already skipped, so a manual seek back sticks
  let video = null;
  let mutedBySegment = false;
  let mutedPrevState = false;

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  function getVideoId() {
    try {
      const url = new URL(location.href);
      const v = url.searchParams.get('v');
      if (v) return v;
      const m = url.pathname.match(/^\/(?:shorts|embed|live)\/([\w-]{11})/);
      return m ? m[1] : null;
    } catch {
      return null;
    }
  }

  async function sha256Hex(text) {
    const bytes = new TextEncoder().encode(text);
    const digest = await crypto.subtle.digest('SHA-256', bytes);
    return [...new Uint8Array(digest)]
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
  }

  function buildQuery() {
    const params = new URLSearchParams();
    Object.keys(SKIP).forEach((c) => params.append('category', c));
    params.append('actionType', 'skip');
    params.append('actionType', 'mute');
    return params;
  }

  async function fetchSegments(videoId) {
    const params = buildQuery();

    // Preferred: privacy-preserving hash-prefix lookup.
    try {
      const prefix = (await sha256Hex(videoId)).slice(0, 4);
      const res = await fetch(`${API}/api/skipSegments/${prefix}?${params}`, {
        credentials: 'omit',
      });
      if (res.ok) {
        const buckets = await res.json();
        const hit = buckets.find((b) => b.videoID === videoId);
        return hit && Array.isArray(hit.segments) ? hit.segments : [];
      }
      if (res.status === 404) return []; // nobody has submitted segments yet
    } catch {
      /* fall through to direct lookup */
    }

    // Fallback: direct lookup. Only reached if crypto.subtle or the hash
    // endpoint is unavailable.
    try {
      const res = await fetch(
        `${API}/api/skipSegments?videoID=${encodeURIComponent(videoId)}&${params}`,
        { credentials: 'omit' }
      );
      return res.ok ? await res.json() : [];
    } catch {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Toast
  // ---------------------------------------------------------------------------
  let toastEl = null;
  let toastTimer = null;

  function toast(message) {
    if (!SHOW_TOAST || !document.body) return;

    if (!toastEl) {
      toastEl = document.createElement('div');
      toastEl.setAttribute('data-sponsorblock-mobile', 'toast');
      Object.assign(toastEl.style, {
        position: 'fixed',
        left: '50%',
        bottom: 'calc(env(safe-area-inset-bottom, 0px) + 84px)',
        transform: 'translateX(-50%)',
        zIndex: '2147483647',
        padding: '8px 14px',
        borderRadius: '999px',
        background: 'rgba(0,0,0,0.82)',
        color: '#fff',
        font: '500 13px/1.3 -apple-system, system-ui, sans-serif',
        letterSpacing: '0.01em',
        pointerEvents: 'none',
        opacity: '0',
        transition: 'opacity 180ms ease',
        maxWidth: '80vw',
        textAlign: 'center',
      });
      document.body.appendChild(toastEl);
    }

    toastEl.textContent = message;
    toastEl.style.opacity = '1';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      if (toastEl) toastEl.style.opacity = '0';
    }, 1600);
  }

  // ---------------------------------------------------------------------------
  // Skipping
  // ---------------------------------------------------------------------------
  function onTimeUpdate() {
    if (!video || !segments.length) return;
    const t = video.currentTime;

    // Mute segments: quiet the audio rather than jumping.
    const inMute = segments.find(
      (s) =>
        s.actionType === 'mute' &&
        SKIP[s.category] &&
        t >= s.segment[0] &&
        t < s.segment[1]
    );
    if (inMute && !mutedBySegment) {
      mutedPrevState = video.muted;
      video.muted = true;
      mutedBySegment = true;
    } else if (!inMute && mutedBySegment) {
      video.muted = mutedPrevState;
      mutedBySegment = false;
    }

    // Skip segments.
    for (const s of segments) {
      if (s.actionType !== 'skip') continue;
      if (!SKIP[s.category]) continue;
      if (handled.has(s.UUID)) continue;

      const [start, end] = s.segment;
      // The 0.2s guard stops us firing on a segment we have already left.
      if (t >= start && t < end - 0.2) {
        handled.add(s.UUID);
        video.currentTime = end;
        toast(`Skipped ${LABEL[s.category] || s.category}`);
        return;
      }
    }
  }

  function bindVideo() {
    const el = document.querySelector('video');
    if (!el || el === video) return;
    if (video) video.removeEventListener('timeupdate', onTimeUpdate);
    video = el;
    video.addEventListener('timeupdate', onTimeUpdate);
  }

  // ---------------------------------------------------------------------------
  // Navigation watch — YouTube is a single-page app, so the URL changes
  // without a reload. Polling is uglier than events but survives every
  // rewrite of YouTube's internals, which is what we want long-term.
  // ---------------------------------------------------------------------------
  async function loadForCurrentVideo() {
    const id = getVideoId();
    if (id === currentVideoId) return;

    currentVideoId = id;
    segments = [];
    handled.clear();

    if (mutedBySegment && video) {
      video.muted = mutedPrevState;
      mutedBySegment = false;
    }
    if (!id) return;

    const found = await fetchSegments(id);
    // Guard against a slow response landing after the user moved on.
    if (getVideoId() !== id) return;
    segments = found;
  }

  setInterval(() => {
    bindVideo();
    loadForCurrentVideo();
  }, 700);

  bindVideo();
  loadForCurrentVideo();
})();
