// ==UserScript==
// @name         Kemono Google Drive Link Copier
// @namespace    http://tampermonkey.net/
// @version      1.0
// @description  Find Google Drive links on Kemono and copy them to clipboard
// @match        https://kemono.cr/patreon/user/3327936/community/*
// @grant        GM_setClipboard
// ==/UserScript==

(function () {
    'use strict';

    function grabLinks() {
        let links = new Set();

        document.querySelectorAll("a[href]").forEach(a => {
            let href = a.href;

            if (href.includes("https://drive.google.com/drive/")) {
                links.add(href);
            }
        });

        if (links.size === 0) {
            console.log("No Google Drive links found.");
            return;
        }

        let output = Array.from(links).join("\n");

        GM_setClipboard(output);

        console.log("Copied links to clipboard:");
        console.log(output);
    }

    window.addEventListener("load", () => {
        setTimeout(grabLinks, 2000);
    });

})();
