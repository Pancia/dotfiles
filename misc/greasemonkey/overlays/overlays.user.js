// ==UserScript==
// @name     Overlays
// @version  37
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

    function closeTo(x, number, margin) {
        return x >= (number - margin) && x <= (number + margin)
    }

    function addIndividualOverlays(containerSelector, itemSelector, config) {
        console.log(`[DEBUG] addIndividualOverlays called with:`, containerSelector, itemSelector, config);
        const container = $(containerSelector)[0];
        if (!container) {
            console.log(`[ERROR] Container ${containerSelector} not found`);
            return;
        }
        console.log(`[DEBUG] Container found:`, container);

        const itemName = config.itemName || 'items';
        const holdTime = config.holdTime || 3000;
        const adjacentRevealCount = config.adjacentRevealCount || 2;
        const filterFunction = config.filterFunction;
        const blurEffect = config.blurEffect || false;

        console.log(`[DEBUG] Adding individual overlays to ${itemName}`);

        // Get all items
        let allItems = Array.from(container.querySelectorAll(itemSelector));
        console.log(`[DEBUG] Found ${allItems.length} items before filtering`);
        if (filterFunction) {
            const beforeFilter = allItems.length;
            allItems = allItems.filter(filterFunction);
            console.log(`[DEBUG] Filtered from ${beforeFilter} to ${allItems.length} items`);
        }
        if (allItems.length === 0) {
            console.log(`[ERROR] No ${itemName} found after filtering`);
            return;
        }

        console.log(`[DEBUG] Found ${allItems.length} ${itemName} to overlay`);

        // Apply blur effect if enabled
        if (blurEffect) {
            addGlobalStyle(`
                ${itemSelector} {
                    filter: blur(5px);
                    transition: filter 0.3s ease;
                }
                ${itemSelector}.revealed {
                    filter: none;
                }
            `);
        }

        // Add overlay to each item
        allItems.forEach((item, index) => {
            if (item.querySelector('.individual-item-overlay')) {
                return;
            }

            if (!item.id) {
                item.id = `${itemName}-item-${index}-${Date.now()}`;
            }

            // Create overlay
            const overlay = document.createElement('div');
            overlay.className = 'individual-item-overlay';
            overlay.dataset.itemType = itemName;
            overlay.dataset.itemIndex = index;
            overlay.style.cssText = `
                position: absolute;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background-color: rgba(0, 0, 0, 0.8);
                z-index: 2000;
                display: flex;
                align-items: center;
                justify-content: center;
                box-sizing: border-box;
                border: 2px solid #065fd4;
                min-height: 50px;
                backdrop-filter: blur(5px);
                -webkit-backdrop-filter: blur(5px);
            `;

            // Add blur layer
            const blurLayer = document.createElement('div');
            blurLayer.style.cssText = `
                position: absolute;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background-color: rgba(255, 255, 255, 0.1);
            `;
            overlay.appendChild(blurLayer);

            // Create reveal button
            const revealButton = document.createElement('button');
            const itemType = itemName === 'comments' ? 'comment' : (itemName === 'videos' ? 'video' : 'item');
            revealButton.textContent = `Reveal this ${itemType} + ${adjacentRevealCount} nearby`;
            revealButton.style.cssText = `
                white-space: nowrap;
                background-color: #065fd4;
                color: white;
                border: none;
                border-radius: 2px;
                padding: 8px 14px;
                font-size: 13px;
                cursor: pointer;
                position: relative;
                z-index: 1;
            `;

            // Add pressAndHold behavior
            $(revealButton).pressAndHold({ holdTime: holdTime });

            // When button is held, remove this overlay and adjacent ones
            $(revealButton).on('complete.pressAndHold', () => {
                overlay.remove();

                // Find and remove adjacent overlays
                const allItems = Array.from(container.querySelectorAll(itemSelector));
                const currentIndex = allItems.indexOf(item);

                const removeAdjacentOverlays = (itemIndex, direction, count) => {
                    for (let i = 1; i <= count; i++) {
                        const adjacentIndex = itemIndex + (direction * i);
                        if (adjacentIndex >= 0 && adjacentIndex < allItems.length) {
                            const adjacentItem = allItems[adjacentIndex];
                            const adjacentOverlay = adjacentItem.querySelector('.individual-item-overlay');
                            if (adjacentOverlay) {
                                adjacentOverlay.remove();
                            }
                            if (blurEffect) {
                                adjacentItem.classList.add('revealed');
                            }
                        }
                    }
                };

                removeAdjacentOverlays(currentIndex, 1, adjacentRevealCount);  // Remove below

                if (blurEffect) {
                    item.classList.add('revealed');
                }

                console.log(`Revealed ${itemName} item at index ${currentIndex} and adjacent items`);
            });

            overlay.appendChild(revealButton);

            // Make sure the item has position relative
            const currentPosition = window.getComputedStyle(item).position;
            if (currentPosition === 'static') {
                item.style.position = 'relative';
            }

            item.appendChild(overlay);
        });

        console.log(`Added overlays to ${allItems.length} ${itemName}`);

        // Set up mutation observer for dynamically added items
        const observer = new MutationObserver(_.debounce(() => {
            let newItems = Array.from(container.querySelectorAll(itemSelector))
                .filter(item => !item.querySelector('.individual-item-overlay'));

            if (filterFunction) {
                newItems = newItems.filter(filterFunction);
            }

            if (newItems.length === 0) return;

            console.log(`New ${itemName} detected, adding overlays to ${newItems.length} items`);

            newItems.forEach((item, index) => {
                if (!item.id) {
                    item.id = `${itemName}-item-new-${index}-${Date.now()}`;
                }

                const overlay = document.createElement('div');
                overlay.className = 'individual-item-overlay';
                overlay.dataset.itemType = itemName;
                overlay.dataset.itemIndex = index;
                overlay.style.cssText = `
                    position: absolute;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    background-color: rgba(0, 0, 0, 0.8);
                    z-index: 2000;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    box-sizing: border-box;
                    border: 2px solid #065fd4;
                    min-height: 50px;
                    backdrop-filter: blur(5px);
                    -webkit-backdrop-filter: blur(5px);
                `;

                const blurLayer = document.createElement('div');
                blurLayer.style.cssText = `
                    position: absolute;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    background-color: rgba(255, 255, 255, 0.1);
                `;
                overlay.appendChild(blurLayer);

                const revealButton = document.createElement('button');
                const itemType = itemName === 'comments' ? 'comment' : (itemName === 'videos' ? 'video' : 'item');
                revealButton.textContent = `Reveal this ${itemType} + ${adjacentRevealCount} nearby`;
                revealButton.style.cssText = `
                    white-space: nowrap;
                    background-color: #065fd4;
                    color: white;
                    border: none;
                    border-radius: 2px;
                    padding: 8px 14px;
                    font-size: 13px;
                    cursor: pointer;
                    position: relative;
                    z-index: 1;
                `;

                $(revealButton).pressAndHold({ holdTime: holdTime });

                $(revealButton).on('complete.pressAndHold', () => {
                    overlay.remove();

                    const allItems = Array.from(container.querySelectorAll(itemSelector));
                    const currentIndex = allItems.indexOf(item);

                    const removeAdjacentOverlays = (itemIndex, direction, count) => {
                        for (let i = 1; i <= count; i++) {
                            const adjacentIndex = itemIndex + (direction * i);
                            if (adjacentIndex >= 0 && adjacentIndex < allItems.length) {
                                const adjacentItem = allItems[adjacentIndex];
                                const adjacentOverlay = adjacentItem.querySelector('.individual-item-overlay');
                                if (adjacentOverlay) {
                                    adjacentOverlay.remove();
                                }
                                if (blurEffect) {
                                    adjacentItem.classList.add('revealed');
                                }
                            }
                        }
                    };

                    removeAdjacentOverlays(currentIndex, 1, adjacentRevealCount);

                    if (blurEffect) {
                        item.classList.add('revealed');
                    }

                    console.log(`Revealed ${itemName} item at index ${currentIndex} and adjacent items`);
                });

                overlay.appendChild(revealButton);

                const currentPosition = window.getComputedStyle(item).position;
                if (currentPosition === 'static') {
                    item.style.position = 'relative';
                }

                item.appendChild(overlay);
            });
        }, 100));

        observer.observe(container, {
            childList: true,
            subtree: true
        });

        return observer;
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
                console.log(`[DEBUG] Processing overlay config:`, overlayConfig);
                // Check if overlay applies to current path
                if (overlayConfig.path && window.location.pathname !== overlayConfig.path) {
                    console.log(`[DEBUG] Skipping - path mismatch: ${window.location.pathname} !== ${overlayConfig.path}`);
                    return;
                }
                if (overlayConfig.pathPattern && !window.location.pathname.match(overlayConfig.pathPattern)) {
                    console.log(`[DEBUG] Skipping - path pattern mismatch`);
                    return;
                }

                // Add the overlay
                if (overlayConfig.individual) {
                    console.log(`[DEBUG] Individual overlay mode for ${overlayConfig.itemName}`);
                    // Individual overlays for each item
                    if (overlayConfig.waitForChild) {
                        console.log(`[DEBUG] Waiting for child: ${overlayConfig.selector} ${overlayConfig.waitForChild}`);
                        waitForElementToBeLoaded(`${overlayConfig.selector} ${overlayConfig.waitForChild}`, () => {
                            console.log(`[DEBUG] Child element loaded, calling addIndividualOverlays`);
                            addIndividualOverlays(overlayConfig.selector, overlayConfig.itemSelector, overlayConfig);
                        });
                    } else if (overlayConfig.waitFor) {
                        console.log(`[DEBUG] Waiting for: ${overlayConfig.selector}`);
                        waitForElementToBeLoaded(overlayConfig.selector, () => {
                            console.log(`[DEBUG] Element loaded, calling addIndividualOverlays`);
                            addIndividualOverlays(overlayConfig.selector, overlayConfig.itemSelector, overlayConfig);
                        });
                    } else {
                        console.log(`[DEBUG] No wait, calling addIndividualOverlays immediately`);
                        addIndividualOverlays(overlayConfig.selector, overlayConfig.itemSelector, overlayConfig);
                    }
                } else {
                    // Section-level overlay
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
                    itemSelector: "#comment",
                    individual: true,
                    itemName: "comments",
                    adjacentRevealCount: 2,
                    holdTime: 3000,
                    blurEffect: false,
                    waitFor: true,
                    filterFunction: (element) => element.offsetHeight > 333
                },
                {
                    path: "/watch",
                    selector: "ytd-watch-next-secondary-results-renderer",
                    itemSelector: ".ytd-item-section-renderer,.ytd-watch-next-secondary-results-renderer",
                    individual: true,
                    itemName: "videos",
                    adjacentRevealCount: 2,
                    holdTime: 3000,
                    blurEffect: true,
                    waitFor: true,
                    filterFunction: function(item) {
                        const thumbnailEl = document.querySelector("ytd-watch-next-secondary-results-renderer a#thumbnail");
                        if (!thumbnailEl) return false;
                        return closeTo(item.offsetHeight, thumbnailEl.offsetHeight, 10);
                    }
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
