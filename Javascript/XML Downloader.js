// ==UserScript==
// @name         XML Sitemap Mass Downloader
// @namespace    http://tampermonkey.net/
// @version      1.0
// @description  Mass download XML pages by iterating a URL parameter
// @author       You
// @match        *://*/*
// @grant        GM_download
// @grant        GM_xmlhttpRequest
// @connect      *
// ==/UserScript==

(function () {
    'use strict';

    // =========================================================
    //  CONFIG — paste your base URL and set your range here
    // =========================================================
    const DEFAULT_URL    = 'https://www.example.com/sitemap.xml?type=videos&from_links_videos=';
    const DEFAULT_START  = 1;       // starting page number
    const DEFAULT_END    = 500;     // ending page number (adjust as needed)
    const DEFAULT_DELAY  = 800;     // milliseconds between each download (increase if site rate-limits you)
    // =========================================================

    let isRunning   = false;
    let stopFlag    = false;
    let currentJob  = null;

    // --- Build the floating UI panel ---
    const panel = document.createElement('div');
    panel.id = 'xml-dl-panel';
    panel.style.cssText = `
        position: fixed;
        top: 20px;
        right: 20px;
        z-index: 999999;
        background: #1e1e2e;
        color: #cdd6f4;
        font-family: monospace;
        font-size: 13px;
        padding: 16px;
        border-radius: 10px;
        box-shadow: 0 4px 24px rgba(0,0,0,0.5);
        width: 340px;
        user-select: none;
    `;

    panel.innerHTML = `
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;">
            <b style="font-size:14px;">🗺️ XML Mass Downloader</b>
            <span id="xml-dl-minimize" style="cursor:pointer;font-size:16px;line-height:1;" title="Minimize">—</span>
        </div>
        <div id="xml-dl-body">
            <label style="display:block;margin-bottom:4px;">Base URL (up to the page number):</label>
            <input id="xml-dl-url" type="text" value="${DEFAULT_URL}"
                style="width:100%;box-sizing:border-box;padding:5px;border-radius:5px;border:1px solid #45475a;background:#313244;color:#cdd6f4;font-size:12px;margin-bottom:8px;" />

            <div style="display:flex;gap:8px;margin-bottom:8px;">
                <div style="flex:1;">
                    <label>Start #</label><br>
                    <input id="xml-dl-start" type="number" value="${DEFAULT_START}" min="0"
                        style="width:100%;box-sizing:border-box;padding:5px;border-radius:5px;border:1px solid #45475a;background:#313244;color:#cdd6f4;" />
                </div>
                <div style="flex:1;">
                    <label>End #</label><br>
                    <input id="xml-dl-end" type="number" value="${DEFAULT_END}" min="1"
                        style="width:100%;box-sizing:border-box;padding:5px;border-radius:5px;border:1px solid #45475a;background:#313244;color:#cdd6f4;" />
                </div>
                <div style="flex:1;">
                    <label>Delay (ms)</label><br>
                    <input id="xml-dl-delay" type="number" value="${DEFAULT_DELAY}" min="100" step="100"
                        style="width:100%;box-sizing:border-box;padding:5px;border-radius:5px;border:1px solid #45475a;background:#313244;color:#cdd6f4;" />
                </div>
            </div>

            <div style="display:flex;gap:8px;margin-bottom:10px;">
                <button id="xml-dl-start-btn"
                    style="flex:1;padding:7px;border-radius:6px;border:none;background:#a6e3a1;color:#1e1e2e;font-weight:bold;cursor:pointer;">
                    ▶ Start
                </button>
                <button id="xml-dl-stop-btn" disabled
                    style="flex:1;padding:7px;border-radius:6px;border:none;background:#f38ba8;color:#1e1e2e;font-weight:bold;cursor:pointer;opacity:0.4;">
                    ■ Stop
                </button>
            </div>

            <!-- Progress bar -->
            <div style="background:#313244;border-radius:5px;height:10px;margin-bottom:6px;overflow:hidden;">
                <div id="xml-dl-bar" style="height:100%;width:0%;background:#89b4fa;transition:width 0.3s;border-radius:5px;"></div>
            </div>

            <div id="xml-dl-status" style="font-size:12px;color:#a6adc8;">Idle. Configure above and press Start.</div>
            <div id="xml-dl-log"
                style="margin-top:8px;max-height:100px;overflow-y:auto;font-size:11px;color:#a6adc8;background:#181825;border-radius:5px;padding:6px;line-height:1.6;">
            </div>
        </div>
    `;

    document.body.appendChild(panel);

    // --- Element refs ---
    const urlInput    = document.getElementById('xml-dl-url');
    const startInput  = document.getElementById('xml-dl-start');
    const endInput    = document.getElementById('xml-dl-end');
    const delayInput  = document.getElementById('xml-dl-delay');
    const startBtn    = document.getElementById('xml-dl-start-btn');
    const stopBtn     = document.getElementById('xml-dl-stop-btn');
    const statusEl    = document.getElementById('xml-dl-status');
    const barEl       = document.getElementById('xml-dl-bar');
    const logEl       = document.getElementById('xml-dl-log');
    const minimizeBtn = document.getElementById('xml-dl-minimize');
    const bodyEl      = document.getElementById('xml-dl-body');

    // --- Minimize toggle ---
    let minimized = false;
    minimizeBtn.addEventListener('click', () => {
        minimized = !minimized;
        bodyEl.style.display = minimized ? 'none' : 'block';
        minimizeBtn.textContent = minimized ? '+' : '—';
    });

    // --- Logging helper ---
    function log(msg, color = '#a6adc8') {
        const line = document.createElement('div');
        line.style.color = color;
        line.textContent = msg;
        logEl.appendChild(line);
        logEl.scrollTop = logEl.scrollHeight;
    }

    function setStatus(msg) {
        statusEl.textContent = msg;
    }

    // --- Sleep helper ---
    function sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    // --- Fetch and download a single XML page ---
    function fetchAndDownload(url, filename) {
        return new Promise((resolve, reject) => {
            GM_xmlhttpRequest({
                method: 'GET',
                url: url,
                onload: function (response) {
                    if (response.status >= 200 && response.status < 300) {
                        const blob = new Blob([response.responseText], { type: 'application/xml' });
                        const blobUrl = URL.createObjectURL(blob);
                        GM_download({
                            url: blobUrl,
                            name: filename,
                            onload: () => { URL.revokeObjectURL(blobUrl); resolve('ok'); },
                            onerror: (err) => { URL.revokeObjectURL(blobUrl); reject(err); }
                        });
                    } else {
                        reject(new Error(`HTTP ${response.status}`));
                    }
                },
                onerror: (err) => reject(err),
                ontimeout: () => reject(new Error('Timeout'))
            });
        });
    }

    // --- Main download loop ---
    async function runDownloads() {
        const baseUrl  = urlInput.value.trim();
        const start    = parseInt(startInput.value, 10);
        const end      = parseInt(endInput.value, 10);
        const delay    = parseInt(delayInput.value, 10);

        if (!baseUrl) { alert('Please enter a base URL.'); return; }
        if (isNaN(start) || isNaN(end) || start > end) { alert('Invalid start/end numbers.'); return; }

        isRunning = true;
        stopFlag  = false;
        startBtn.disabled = true;
        startBtn.style.opacity = '0.4';
        stopBtn.disabled = false;
        stopBtn.style.opacity = '1';
        logEl.innerHTML = '';

        const total = end - start + 1;
        let done = 0, failed = 0;

        log(`Starting: pages ${start} → ${end} (${total} files)`, '#89b4fa');

        for (let i = start; i <= end; i++) {
            if (stopFlag) {
                log('⛔ Stopped by user.', '#f38ba8');
                setStatus(`Stopped at page ${i}. Downloaded ${done}, failed ${failed}.`);
                break;
            }

            const url      = baseUrl + i;
            const filename = `sitemap_page_${i}.xml`;

            setStatus(`Downloading page ${i} of ${end}... (${done}/${total})`);

            try {
                await fetchAndDownload(url, filename);
                done++;
                log(`✔ Page ${i}`, '#a6e3a1');
            } catch (err) {
                failed++;
                log(`✘ Page ${i} — ${err.message || err}`, '#f38ba8');
            }

            // Update progress bar
            const pct = ((i - start + 1) / total) * 100;
            barEl.style.width = pct + '%';

            if (i < end && !stopFlag) {
                await sleep(delay);
            }
        }

        if (!stopFlag) {
            setStatus(`✅ Done! Downloaded ${done} files, ${failed} failed.`);
            log(`Finished. ${done} succeeded, ${failed} failed.`, '#89dceb');
        }

        isRunning = false;
        startBtn.disabled = false;
        startBtn.style.opacity = '1';
        stopBtn.disabled = true;
        stopBtn.style.opacity = '0.4';
    }

    startBtn.addEventListener('click', () => { if (!isRunning) runDownloads(); });
    stopBtn.addEventListener('click',  () => { if (isRunning)  stopFlag = true; });

})();
