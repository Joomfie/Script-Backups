// ==UserScript==
// @name         Kemono Link Auto Copier
// @namespace    https://kemono.cr/
// @version      1.1
// @description  Automatically detects Mega, Google Drive, and Dropbox links on Kemono and copies them to clipboard
// @match        https://kemono.cr/*
// @grant        GM_setClipboard
// @grant        GM_notification
// @grant        GM_getValue
// @grant        GM_setValue
// ==/UserScript==
(function () {
    'use strict';

    const copiedLinks = new Set();

    const linkPatterns = [
        /https?:\/\/mega\.nz\/[^\s"'<>\\]+/gi,
        /https?:\/\/drive\.google\.com\/[^\s"'<>\\]+/gi,
        /https?:\/\/www\.dropbox\.com\/[^\s"'<>\\]+/gi
    ];

    function decodeEntities(str) {
        return str
            .replace(/&#35;/g, '#')
            .replace(/&#47;/g, '/')
            .replace(/&amp;/g, '&')
            .replace(/&#38;/g, '&')
            .replace(/&#61;/g, '=')
            .replace(/&#43;/g, '+');
    }

    function processLink(link) {
        return link.replace(/[.,;!?)]+$/, '');
    }

    function handleNewLink(clean, source) {
        copiedLinks.add(clean);
        GM_setClipboard(clean);
        console.log(`[Kemono Auto Copy] Copied (${source}):`, clean);

        // Optional: Desktop notification per found link
        GM_notification({
            title: 'Kemono Auto Copy',
            text: `Copied ${source} link to clipboard`,
            timeout: 3000
        });
    }

    function scanAndCopy() {
        // --- Pass 1: Decode & scan raw innerHTML ---
        const decoded = decodeEntities(document.body.innerHTML);
        linkPatterns.forEach(pattern => {
            pattern.lastIndex = 0;
            const matches = decoded.match(pattern);
            if (!matches) return;
            matches.forEach(link => {
                const clean = processLink(link);
                if (!copiedLinks.has(clean)) handleNewLink(clean, 'HTML');
            });
        });

        // --- Pass 2: Walk anchor hrefs (browser auto-decodes percent-encoding) ---
        document.querySelectorAll('a[href]').forEach(anchor => {
            let href = decodeEntities(anchor.href);
            linkPatterns.forEach(pattern => {
                pattern.lastIndex = 0;
                if (pattern.test(href)) {
                    const clean = processLink(href);
                    if (!copiedLinks.has(clean)) handleNewLink(clean, 'anchor');
                }
            });
        });

        // --- Pass 3: Scan visible text nodes in post content ---
        document.querySelectorAll('.post__content, .post__body, p, li').forEach(el => {
            const text = el.innerText || el.textContent;
            linkPatterns.forEach(pattern => {
                pattern.lastIndex = 0;
                const matches = text.match(pattern);
                if (!matches) return;
                matches.forEach(link => {
                    const clean = processLink(link);
                    if (!copiedLinks.has(clean)) handleNewLink(clean, 'text node');
                });
            });
        });
    }

    // Give the page time to fully render before first scan
    setTimeout(scanAndCopy, 1500);

    // Watch for dynamically loaded content
    const observer = new MutationObserver(scanAndCopy);
    observer.observe(document.body, {
        childList: true,
        subtree: true
    });
})();
