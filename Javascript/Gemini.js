// ==UserScript==
// @name         Gemini Redo on Left Ctrl (Debug)
// @namespace    http://tampermonkey.net/
// @version      1.3
// @description  Press Left Ctrl to Redo, double-tap Left Ctrl to Try Again. Skips when editing text.
// @author       You
// @match        https://gemini.google.com/*
// @grant        none
// @run-at       document-start
// ==/UserScript==
(function () {
  'use strict';
  console.log('[Gemini Redo] ✅ Script loaded and running.');

  // ─── Helpers ────────────────────────────────────────────────────────────────

  function isEditingText() {
    const el = document.activeElement;
    if (!el) return false;

    const tag = el.tagName.toLowerCase();

    // Standard text inputs and textareas
    if (tag === 'textarea') return true;
    if (tag === 'input') {
      const type = (el.getAttribute('type') || 'text').toLowerCase();
      const textTypes = ['text', 'search', 'email', 'url', 'password', 'number', 'tel'];
      if (textTypes.includes(type)) return true;
    }

    // Contenteditable elements (Gemini's rich prompt box)
    if (el.isContentEditable) return true;

    // Walk up the DOM — Gemini may focus a child of the editable div
    let node = el.parentElement;
    while (node && node !== document.body) {
      if (node.isContentEditable) return true;
      node = node.parentElement;
    }

    return false;
  }

  function findButtons(labelHints) {
    const allButtons = Array.from(document.querySelectorAll('button'));
    return allButtons.filter(btn => {
      const label = (btn.getAttribute('aria-label') || '').toLowerCase();
      const title = (btn.getAttribute('title') || '').toLowerCase();
      const mat   = (btn.getAttribute('mattooltip') || '').toLowerCase();
      const text  = (btn.innerText || '').toLowerCase().trim();
      return labelHints.some(hint =>
        label.includes(hint) || title.includes(hint) || mat.includes(hint) || text === hint
      );
    });
  }

  // ─── Actions ────────────────────────────────────────────────────────────────

  function clickLastRedoButton() {
    console.log('[Gemini Redo] Searching for Redo button...');

    // Preferred: exact attribute selectors
    const selectors = [
      'button[aria-label="Redo"]',
      'button[aria-label="redo"]',
      'button[title="Redo"]',
      'button[title="redo"]',
      'button[data-tooltip="Redo"]',
      'button[mattooltip="Redo"]',
    ];

    let redoButtons = [];
    for (const selector of selectors) {
      const found = Array.from(document.querySelectorAll(selector));
      if (found.length > 0) {
        console.log(`[Gemini Redo] Found via selector: ${selector}`);
        redoButtons = found;
        break;
      }
    }

    // Broad text fallback
    if (redoButtons.length === 0) {
      redoButtons = findButtons(['redo']);
      console.log(`[Gemini Redo] Broad fallback found ${redoButtons.length} redo button(s).`);
    }

    if (redoButtons.length === 0) {
      console.warn('[Gemini Redo] ❌ No Redo button found.');
      return false;
    }

    const target = redoButtons[redoButtons.length - 1];
    console.log('[Gemini Redo] Clicking Redo:', target);
    target.style.visibility = 'visible';
    target.style.opacity = '1';
    target.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
    console.log('[Gemini Redo] ✅ Redo click dispatched.');
    return true;
  }

  function clickLastTryAgainButton() {
    console.log('[Gemini Redo] Searching for Try Again button...');

    // Gemini may label this button differently — cover common variants
    const hints = ['try again', 'regenerate', 'retry', 'try again'];
    const tryAgainButtons = findButtons(hints);

    console.log(`[Gemini Redo] Found ${tryAgainButtons.length} Try Again button(s).`);

    if (tryAgainButtons.length === 0) {
      console.warn('[Gemini Redo] ❌ No Try Again button found.');
      return false;
    }

    const target = tryAgainButtons[tryAgainButtons.length - 1];
    console.log('[Gemini Redo] Clicking Try Again:', target);
    target.style.visibility = 'visible';
    target.style.opacity = '1';
    target.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
    console.log('[Gemini Redo] ✅ Try Again click dispatched.');
    return true;
  }

  // ─── Key Handler ────────────────────────────────────────────────────────────

  // Double-tap detection state
  let lastCtrlTime = 0;
  const DOUBLE_TAP_WINDOW = 400; // ms between two Left Ctrl presses
  const DEBOUNCE = 500;          // ms minimum between any two actions
  let lastFired = 0;

  const handler = function (e) {
    if (e.code !== 'ControlLeft') return;
    if (e.altKey || e.shiftKey || e.metaKey) return;

    // Skip entirely when the user is typing / has text selected in an input
    if (isEditingText()) {
      console.log('[Gemini Redo] Skipping — text field is active.');
      return;
    }

    const now = Date.now();

    // Global debounce — prevent firing twice from the paired window+document listeners
    if (now - lastFired < DEBOUNCE) return;

    const timeSinceLast = now - lastCtrlTime;
    const isDoubleTap   = timeSinceLast < DOUBLE_TAP_WINDOW;

    e.preventDefault();
    e.stopPropagation();

    if (isDoubleTap) {
      // ── Double-tap → Try Again ──────────────────────────────────────────────
      console.log('[Gemini Redo] Double-tap detected → Try Again');
      lastCtrlTime = 0; // reset so a third tap starts fresh
      lastFired = now;
      clickLastTryAgainButton();
    } else {
      // ── Single tap → Redo ───────────────────────────────────────────────────
      console.log('[Gemini Redo] Single tap → Redo');
      lastCtrlTime = now;
      lastFired = now;
      clickLastRedoButton();
    }
  };

  document.addEventListener('keydown', handler, true);
  window.addEventListener('keydown', handler, true);
})();
