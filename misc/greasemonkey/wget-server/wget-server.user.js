// ==UserScript==
// @name         wget_server YouTube Downloader
// @namespace    http://dotfiles.local/
// @version      1.0
// @description  Download YouTube videos via wget_server API with two-step workflow
// @match        *://www.youtube.com/*
// @match        *://youtube.com/*
// @grant        GM_xmlhttpRequest
// @grant        GM_setValue
// @grant        GM_getValue
// @grant        GM_registerMenuCommand
// @require      http://code.jquery.com/jquery-latest.min.js
// @connect      *
// ==/UserScript==

(function($, window, document) {
    'use strict';

    // =========================================================================
    // Config Manager
    // =========================================================================

    const CONFIG_KEYS = {
        SERVER_URL: 'wget_server_url',
        USERNAME: 'wget_server_username',
        PASSWORD: 'wget_server_password'
    };

    function getConfig() {
        return {
            serverUrl: GM_getValue(CONFIG_KEYS.SERVER_URL, ''),
            username: GM_getValue(CONFIG_KEYS.USERNAME, ''),
            password: GM_getValue(CONFIG_KEYS.PASSWORD, '')
        };
    }

    function saveConfig(serverUrl, username, password) {
        GM_setValue(CONFIG_KEYS.SERVER_URL, serverUrl);
        GM_setValue(CONFIG_KEYS.USERNAME, username);
        GM_setValue(CONFIG_KEYS.PASSWORD, password);
    }

    function isConfigured() {
        const config = getConfig();
        return config.serverUrl && config.username && config.password;
    }

    function getAuthHeader() {
        const config = getConfig();
        return 'Basic ' + btoa(config.username + ':' + config.password);
    }

    // =========================================================================
    // API Client
    // =========================================================================

    function apiRequest(endpoint, method, data) {
        return new Promise((resolve, reject) => {
            const config = getConfig();
            const url = config.serverUrl.replace(/\/$/, '') + endpoint;

            GM_xmlhttpRequest({
                method: method,
                url: url,
                headers: {
                    'Authorization': getAuthHeader(),
                    'Content-Type': 'application/json'
                },
                data: data ? JSON.stringify(data) : null,
                onload: function(response) {
                    if (response.status >= 200 && response.status < 300) {
                        try {
                            resolve(JSON.parse(response.responseText));
                        } catch (e) {
                            resolve(response.responseText);
                        }
                    } else {
                        reject({
                            status: response.status,
                            message: response.responseText
                        });
                    }
                },
                onerror: function(error) {
                    reject({
                        status: 0,
                        message: 'Network error: ' + error.statusText
                    });
                }
            });
        });
    }

    function fetchModes() {
        return apiRequest('/modes', 'GET');
    }

    function planDownload(url, mode) {
        return apiRequest('/download/plan', 'POST', { url: url, mode: mode });
    }

    function executeDownload(items) {
        return apiRequest('/download/execute', 'POST', { items: items });
    }

    // =========================================================================
    // UI Components
    // =========================================================================

    const STYLES = `
        .wget-overlay {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background-color: rgba(0, 0, 0, 0.7);
            z-index: 99998;
        }

        .wget-modal {
            display: none;
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            background-color: #1a1a1a;
            border-radius: 12px;
            padding: 24px;
            min-width: 400px;
            max-width: 500px;
            z-index: 99999;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            color: #fff;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.4);
        }

        .wget-modal h2 {
            margin: 0 0 20px 0;
            font-size: 20px;
            font-weight: 600;
        }

        .wget-modal label {
            display: block;
            margin-bottom: 6px;
            font-size: 14px;
            color: #aaa;
        }

        .wget-modal input,
        .wget-modal select,
        .wget-modal textarea {
            width: 100%;
            padding: 10px 12px;
            margin-bottom: 16px;
            border: 1px solid #333;
            border-radius: 6px;
            background-color: #2a2a2a;
            color: #fff;
            font-size: 14px;
            box-sizing: border-box;
        }

        .wget-modal input:focus,
        .wget-modal select:focus,
        .wget-modal textarea:focus {
            outline: none;
            border-color: #ff0000;
        }

        .wget-modal textarea {
            resize: vertical;
            min-height: 60px;
        }

        .wget-modal .button-row {
            display: flex;
            gap: 12px;
            justify-content: flex-end;
            margin-top: 20px;
        }

        .wget-modal button {
            padding: 10px 20px;
            border: none;
            border-radius: 6px;
            font-size: 14px;
            font-weight: 500;
            cursor: pointer;
            transition: background-color 0.2s;
        }

        .wget-modal button.primary {
            background-color: #ff0000;
            color: #fff;
        }

        .wget-modal button.primary:hover {
            background-color: #cc0000;
        }

        .wget-modal button.secondary {
            background-color: #333;
            color: #fff;
        }

        .wget-modal button.secondary:hover {
            background-color: #444;
        }

        .wget-modal button:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }

        .wget-modal .info-row {
            padding: 8px 12px;
            background-color: #2a2a2a;
            border-radius: 6px;
            margin-bottom: 16px;
            font-size: 13px;
            word-break: break-all;
        }

        .wget-modal .info-row .label {
            color: #888;
            margin-right: 8px;
        }

        .wget-toast {
            position: fixed;
            bottom: 24px;
            right: 24px;
            padding: 14px 20px;
            border-radius: 8px;
            font-size: 14px;
            z-index: 100000;
            animation: wget-toast-in 0.3s ease;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        }

        .wget-toast.success {
            background-color: #1a472a;
            color: #4ade80;
        }

        .wget-toast.error {
            background-color: #4a1a1a;
            color: #f87171;
        }

        @keyframes wget-toast-in {
            from {
                opacity: 0;
                transform: translateY(20px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }

        .wget-btn {
            color: #ff0000;
            font-size: 20px;
            cursor: pointer;
            padding: 0 8px;
            user-select: none;
        }

        .wget-btn:hover {
            opacity: 0.8;
        }

        .wget-loading {
            display: inline-block;
            width: 16px;
            height: 16px;
            border: 2px solid #333;
            border-top-color: #ff0000;
            border-radius: 50%;
            animation: wget-spin 0.8s linear infinite;
            margin-right: 8px;
            vertical-align: middle;
        }

        @keyframes wget-spin {
            to { transform: rotate(360deg); }
        }
    `;

    function injectStyles() {
        const style = document.createElement('style');
        style.textContent = STYLES;
        document.head.appendChild(style);
    }

    function createOverlay() {
        const overlay = $('<div>').addClass('wget-overlay');
        overlay.on('click', closeModal);
        $('body').append(overlay);
        return overlay;
    }

    function createModal() {
        const modal = $('<div>').addClass('wget-modal').attr('id', 'wget-modal');
        $('body').append(modal);
        return modal;
    }

    function showModal(content) {
        $('.wget-overlay').show();
        $('#wget-modal').html(content).show();
    }

    function closeModal() {
        $('.wget-overlay').hide();
        $('#wget-modal').hide();
    }

    function showToast(message, type = 'success') {
        const toast = $('<div>')
            .addClass('wget-toast')
            .addClass(type)
            .text(message);

        $('body').append(toast);

        setTimeout(() => {
            toast.fadeOut(300, () => toast.remove());
        }, 4000);
    }

    // =========================================================================
    // Dialog Builders
    // =========================================================================

    function showSetupDialog() {
        const config = getConfig();
        const content = `
            <h2>wget_server Setup</h2>
            <label for="wget-server-url">Server URL</label>
            <input type="text" id="wget-server-url" placeholder="http://192.168.0.100:5000" value="${config.serverUrl}">
            <label for="wget-username">Username</label>
            <input type="text" id="wget-username" placeholder="admin" value="${config.username}">
            <label for="wget-password">Password</label>
            <input type="password" id="wget-password" placeholder="password" value="${config.password}">
            <div class="button-row">
                <button class="secondary" id="wget-cancel">Cancel</button>
                <button class="primary" id="wget-save-config">Save</button>
            </div>
        `;

        showModal(content);

        $('#wget-cancel').on('click', closeModal);
        $('#wget-save-config').on('click', function() {
            const serverUrl = $('#wget-server-url').val().trim();
            const username = $('#wget-username').val().trim();
            const password = $('#wget-password').val();

            if (!serverUrl || !username || !password) {
                showToast('All fields are required', 'error');
                return;
            }

            saveConfig(serverUrl, username, password);
            closeModal();
            showToast('Configuration saved');
        });
    }

    function showModeDialog(modes, currentUrl) {
        const modeOptions = modes.map(m => `<option value="${m}">${m}</option>`).join('');
        const typeOptions = ['video', 'audio', 'text'].map(t =>
            `<option value="${t}"${t === 'video' ? ' selected' : ''}>${t}</option>`
        ).join('');

        const content = `
            <h2>Download Video</h2>
            <div class="info-row">
                <span class="label">URL:</span>${currentUrl}
            </div>
            <label for="wget-mode">Mode</label>
            <select id="wget-mode">
                <option value="">-- Select Mode --</option>
                ${modeOptions}
            </select>
            <label for="wget-type">Type</label>
            <select id="wget-type">
                ${typeOptions}
            </select>
            <label for="wget-notes">Notes (optional)</label>
            <textarea id="wget-notes" placeholder="Add notes about this download..."></textarea>
            <div class="button-row">
                <button class="secondary" id="wget-cancel">Cancel</button>
                <button class="primary" id="wget-plan">Plan Download</button>
            </div>
        `;

        showModal(content);

        $('#wget-cancel').on('click', closeModal);
        $('#wget-plan').on('click', async function() {
            const mode = $('#wget-mode').val();
            const type = $('#wget-type').val();
            const notes = $('#wget-notes').val().trim();

            if (!mode) {
                showToast('Please select a mode', 'error');
                return;
            }

            $(this).prop('disabled', true).html('<span class="wget-loading"></span>Planning...');

            try {
                const plan = await planDownload(currentUrl, mode);
                if (plan.items && plan.items.length > 0) {
                    showPlanDialog(plan.items[0], type, notes);
                } else {
                    showToast('No plan returned from server', 'error');
                }
            } catch (err) {
                showToast('Plan failed: ' + (err.message || err.status), 'error');
                $(this).prop('disabled', false).text('Plan Download');
            }
        });
    }

    function showPlanDialog(planItem, selectedType, notes) {
        const videoTitle = document.querySelector('h1.ytd-watch-metadata yt-formatted-string')?.textContent
            || document.querySelector('h1.title')?.textContent
            || 'Unknown Title';

        const methodOptions = planItem.available_methods.map(m =>
            `<option value="${m}"${m === planItem.detected_method ? ' selected' : ''}>${m}</option>`
        ).join('');

        const typeOptions = (planItem.yt_dlp_types || ['video', 'audio', 'text']).map(t =>
            `<option value="${t}"${t === selectedType ? ' selected' : ''}>${t}</option>`
        ).join('');

        const showFilename = planItem.detected_method !== 'yt-dlp';
        const filenameSection = showFilename ? `
            <label for="wget-filename">Filename</label>
            <input type="text" id="wget-filename" value="${planItem.predicted_filename}">
        ` : `
            <div class="info-row">
                <span class="label">Filename:</span>(auto-generated by yt-dlp)
            </div>
        `;

        const content = `
            <h2>Confirm Download</h2>
            <div class="info-row">
                <span class="label">Title:</span>${videoTitle}
            </div>
            <label for="wget-method">Method</label>
            <select id="wget-method">
                ${methodOptions}
            </select>
            <label for="wget-exec-type">Type</label>
            <select id="wget-exec-type">
                ${typeOptions}
            </select>
            ${filenameSection}
            <label for="wget-exec-notes">Notes</label>
            <textarea id="wget-exec-notes">${notes}</textarea>
            <div class="button-row">
                <button class="secondary" id="wget-back">Back</button>
                <button class="primary" id="wget-execute">Download</button>
            </div>
        `;

        showModal(content);

        $('#wget-back').on('click', async function() {
            try {
                const modesData = await fetchModes();
                showModeDialog(modesData.modes, planItem.url);
            } catch (err) {
                showToast('Failed to fetch modes', 'error');
            }
        });

        $('#wget-execute').on('click', async function() {
            const method = $('#wget-method').val();
            const type = $('#wget-exec-type').val();
            const filename = $('#wget-filename').val()?.trim() || null;
            const execNotes = $('#wget-exec-notes').val().trim();

            $(this).prop('disabled', true).html('<span class="wget-loading"></span>Starting...');

            const item = {
                url: planItem.url,
                method: method,
                mode: planItem.mode,
                yt_dlp_type: type
            };

            if (filename) {
                item.filename = filename;
            }
            if (execNotes) {
                item.notes = execNotes;
            }

            try {
                await executeDownload([item]);
                closeModal();
                showToast('Download started!');
            } catch (err) {
                showToast('Download failed: ' + (err.message || err.status), 'error');
                $(this).prop('disabled', false).text('Download');
            }
        });
    }

    // =========================================================================
    // Main Logic
    // =========================================================================

    function getCurrentUrl() {
        const url = new URL(window.location.href);
        // Clean up YouTube URL - keep only essential params
        const allowedParams = ['v', 'list'];
        const params = new URLSearchParams();

        for (const key of allowedParams) {
            if (url.searchParams.has(key)) {
                params.set(key, url.searchParams.get(key));
            }
        }

        return url.origin + url.pathname + (params.toString() ? '?' + params.toString() : '');
    }

    async function handleDownloadClick() {
        if (!isConfigured()) {
            showSetupDialog();
            return;
        }

        try {
            const modesData = await fetchModes();
            showModeDialog(modesData.modes, getCurrentUrl());
        } catch (err) {
            if (err.status === 401) {
                showToast('Authentication failed - check credentials', 'error');
                showSetupDialog();
            } else {
                showToast('Failed to connect: ' + (err.message || 'Network error'), 'error');
            }
        }
    }

    function waitForElement(selector, callback) {
        const tid = setInterval(function() {
            const el = $(selector)[0];
            if (!el) return;
            clearInterval(tid);
            callback(el);
        }, 100);
    }

    function injectButton() {
        waitForElement('.ytd-masthead', () => {
            waitForElement('#avatar-btn', () => {
                // Don't inject if already present
                if ($('#wget-server-btn').length > 0) return;

                const btn = $('<span>')
                    .attr('id', 'wget-server-btn')
                    .addClass('wget-btn')
                    .text('📥')
                    .attr('title', 'Download with wget_server')
                    .on('click', handleDownloadClick);

                $('.ytd-masthead > #end').before(btn);
            });
        });
    }

    function init() {
        // Prevent running in iframes
        if (window.top !== window.self) return;

        injectStyles();
        createOverlay();
        createModal();
        injectButton();

        // Re-inject on SPA navigation
        let lastUrl = location.href;
        new MutationObserver(() => {
            if (location.href !== lastUrl) {
                lastUrl = location.href;
                injectButton();
            }
        }).observe(document.body, { childList: true, subtree: true });

        // Register menu command for settings
        GM_registerMenuCommand('wget_server Settings', showSetupDialog);
    }

    // Wait for DOM
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

})(jQuery, window, document);
