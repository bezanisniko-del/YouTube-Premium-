// ==UserScript==
// @name         YouTube Ad Skip (fallback layer)
// @namespace    https://github.com/bezanisniko-del/YouTube-Premium-
// @version      1.0.0
// @description  Optional backstop for uBlock Origin Lite. Clicks "Skip Ad" and fast-forwards unskippable in-stream ads. Only install this if you actually see ads getting through.
// @match        *://m.youtube.com/*
// @match        *://www.youtube.com/*
// @match        *://music.youtube.com/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

/*
 * OPTIONAL. uBlock Origin Lite in Optimal/Complete mode should stop YouTube
 * ads before they ever reach the player. Install this only if some slip
 * through — it operates on the player after the fact rather than blocking
 * the request, so it is the cruder of the two mechanisms.
 *
 * Deliberately conservative: it only touches the page while YouTube itself
 * says an ad is showing, so it should sit inert the rest of the time.
 */

(function () {
  'use strict';

  const SKIP_BUTTONS = [
    '.ytp-ad-skip-button',
    '.ytp-ad-skip-button-modern',
    '.ytp-skip-ad-button',
    '.videoAdUiSkipButton',
    'button[class*="ytp-ad-skip"]',
  ].join(',');

  const AD_MARKERS = [
    '#movie_player.ad-showing',
    '.html5-video-player.ad-showing',
    '.ad-showing',
    '.ytp-ad-player-overlay',
    '.ytp-ad-player-overlay-layout',
  ].join(',');

  function isVisible(el) {
    if (!el) return false;
    const rect = el.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }

  function adIsPlaying() {
    return Boolean(document.querySelector(AD_MARKERS));
  }

  function tick() {
    if (!adIsPlaying()) return;

    // 1. If YouTube is offering a skip button, press it.
    const button = document.querySelector(SKIP_BUTTONS);
    if (isVisible(button)) {
      button.click();
      return;
    }

    // 2. Otherwise fast-forward the ad. Seeking to the end of the ad's own
    //    video track lets the player move on to the real content.
    const video = document.querySelector('video');
    if (video && Number.isFinite(video.duration) && video.duration > 0) {
      if (video.currentTime < video.duration - 0.3) {
        video.currentTime = video.duration;
      }
    }
  }

  setInterval(tick, 500);
})();
