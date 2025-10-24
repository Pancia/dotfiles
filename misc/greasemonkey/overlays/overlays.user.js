// ==UserScript==
// @name     Overlays
// @version  35
// @require  http://code.jquery.com/jquery-latest.min.js
// @require  https://cdn.jsdelivr.net/npm/js-cookie@3.0.1/dist/js.cookie.min.js
// @require  https://raw.githubusercontent.com/jashkenas/underscore/master/underscore.js
// @require  https://raw.githubusercontent.com/pancia/dotfiles/master/misc/greasemonkey/overlays/pressAndHold.js
// @grant    none
// ==/UserScript==

(function($, window, document) {
    document.addEventListener('keydown', (event) => {
        if (window.location.host == "www.youtube.com" && window.location.pathname == "/watch") {
            const activeElement = document.activeElement;
            const isInputField = ['input', 'textarea'].includes(activeElement.tagName.toLowerCase());
            console.log(event, activeElement, isInputField)
            if (event.key === 'n' && !event.shiftKey && !isInputField) {
                document.querySelector(".ytp-next-button").click();
            }
        }
    });
})(jQuery, window, document);

(function($) {
    function addOverlay(selector, text, holdTime) {
        var $overlay = $(`<div id='${selector}'></div>`)
            .width($(selector).width())
            .css({
                'opacity' : 1,
                'position': 'absolute',
                'background-color': 'black',
                'height': '100%',
                'z-index': 2200
            });
        $('<button>', {
            'text': text || `Show: ${selector}`
        }).css({
            'height': '100px',
            'width': '100%',
            'font-size': '22px',
            'background-color': 'white'
        }).pressAndHold({holdTime: holdTime || 5000}).on("complete.pressAndHold", () => {
            $(`[id='${selector}']`).remove();
        }).appendTo($overlay);
        $overlay.prependTo(selector)
    }

    function waitForElementToBeLoaded(selector, callback) {
        var tid = setInterval(function() {
            // wait for x element to have been loaded, ie: not null & has width
            var x = $(selector)[0]
            if (x == null || $(x).width() <= 0) { return }
            // x was loaded, go ahead!
            clearInterval(tid)
            callback(x)
        }, 100);
    }

    function addGlobalStyle(css) {
        var head, style;
        head = document.getElementsByTagName('head')[0];
        if (!head) { return; }
        style = document.createElement('style');
        style.type = 'text/css';
        style.innerHTML = css;
        head.appendChild(style);
    }

    function addOverlayTo(element, overlayID, button, opts) {
        var $overlay = $(`<div id='${overlayID}'></div>`)
            .width($(element).width())
            .css({
                'opacity' : 1,
                'position': 'absolute',
                'background-color': 'black',
                'height': '100%',
                'z-index': 2200
            });
        button.pressAndHold(opts).on("complete.pressAndHold", () => {
            try{ element.setAttribute("data-overlay", "disabled"); }catch(e){}
            $(`[id='${overlayID}']`).remove();
        }).appendTo($overlay);
        $overlay.prependTo(element);
    }

    function displayTime(date) {
        return new Date(Number(date)).toLocaleTimeString("en-US", { hour: "numeric", minute: "numeric", hourCycle: "h24"})
    }

    // Process overlays from configuration
    function processOverlayConfig(siteConfig) {
        if (!siteConfig) return;

        // Check if current path is excluded
        if (siteConfig.excludePaths) {
            for (let pattern of siteConfig.excludePaths) {
                if (window.location.pathname.match(pattern)) {
                    return;
                }
            }
        }

        // Apply global styles
        if (siteConfig.globalStyles) {
            addGlobalStyle(siteConfig.globalStyles);
        }

        // Process overlay configurations
        if (siteConfig.overlays) {
            siteConfig.overlays.forEach(overlayConfig => {
                // Check if overlay applies to current path
                if (overlayConfig.path && window.location.pathname !== overlayConfig.path) {
                    return;
                }
                if (overlayConfig.pathPattern && !window.location.pathname.match(overlayConfig.pathPattern)) {
                    return;
                }

                // Add the overlay
                if (overlayConfig.waitForChild) {
                    waitForElementToBeLoaded(`${overlayConfig.selector} ${overlayConfig.waitForChild}`, () => {
                        addOverlay(overlayConfig.selector, overlayConfig.text, overlayConfig.holdTime);
                    });
                } else if (overlayConfig.waitFor) {
                    waitForElementToBeLoaded(overlayConfig.selector, () => {
                        addOverlay(overlayConfig.selector, overlayConfig.text, overlayConfig.holdTime);
                    });
                } else {
                    addOverlay(overlayConfig.selector, overlayConfig.text, overlayConfig.holdTime);
                }
            });
        }

        // Run custom handler for current path
        if (siteConfig.customHandlers) {
            const handler = siteConfig.customHandlers[window.location.pathname];
            if (handler && typeof handler === 'function') {
                handler();
            }
        }
    }

    // Configuration Object
    const OVERLAY_CONFIG = {
        "www.youtube.com": {
            globalStyles: '#contents { filter: grayscale(1); }',
            excludePaths: [/^\/embed/],
            overlays: [
                {
                    path: "/watch",
                    selector: "#comments",
                    waitForChild: "#comment",
                    text: "STOP! is it really worth it?",
                    holdTime: 10000
                },
                {
                    path: "/watch",
                    selector: "#related",
                    waitForChild: "#items",
                    text: "related videos",
                    holdTime: 10000
                }
            ]
        }/*,
        "www.linkedin.com": {
            overlays: [
                { selector: ".news-module", waitFor: true },
                { path: "/feed/", selector: "#main", waitFor: true },
                { path: "/notifications/", selector: "#main", waitFor: true },
                { pathPattern: /^\/news\/daily-rundown\//, selector: "#main", waitFor: true }
            ]
        }*/
    };

    function MAIN() {
        // Process config-driven overlays
        const siteConfig = OVERLAY_CONFIG[window.location.host];
        processOverlayConfig(siteConfig);
    }

    var onMutationsFinished = _.debounce((_) => {
        if (this.lastUrl !== location.href || ! this.lastUrl) {
            this.lastUrl = location.href;
            MAIN();
        }
    }, 100);
    var observer = new MutationObserver(onMutationsFinished);
    observer.observe(document, {subtree: true, childList: true});
})(jQuery);
