// ==UserScript==
// @name     Overlays
// @version  41
// @require  http://code.jquery.com/jquery-latest.min.js
// @require  https://cdn.jsdelivr.net/npm/js-cookie@3.0.1/dist/js.cookie.min.js
// @require  https://raw.githubusercontent.com/jashkenas/underscore/master/underscore.js
// @require  https://raw.githubusercontent.com/pancia/dotfiles/master/misc/greasemonkey/overlays/pressAndHold.js
// @grant    none
// ==/UserScript==
(function($, window, document) {
    const OVERLAY_CONFIG = {
        "www.youtube.com": {
            globalStyles: '#contents { filter: grayscale(1); }',
            excludePaths: [/^\/embed/],
            overlays: [
                {
                    path: "/watch",
                    selector: "#comments #contents",
                    itemSelector: "ytd-comment-thread-renderer",
                    individual: true,
                    itemName: "comments",
                    adjacentRevealCount: 2,
                    holdTime: 3000,
                    blurEffect: true,
                    waitFor: true
                },
                {
                    path: "/watch",
                    selector: "ytd-watch-next-secondary-results-renderer #contents",
                    itemSelector: ".ytd-item-section-renderer,.ytd-watch-next-secondary-results-renderer",
                    individual: true,
                    itemName: "videos",
                    adjacentRevealCount: 2,
                    holdTime: 3000,
                    blurEffect: true,
                    waitFor: true
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

    function waitForElementToBeLoaded(selector, callback, validationFn) {
        var tid = setInterval(function() {
            // wait for x element to have been loaded, ie: not null & has width
            var x = $(selector)[0]
            if (x == null || $(x).width() <= 0) { return }

            // Optional validation function (e.g., check for children)
            if (validationFn && !validationFn(x)) {
                console.log(`[DEBUG] Element ${selector} found but validation failed, waiting...`);
                return;
            }

            // x was loaded and validated, go ahead!
            console.log(`[DEBUG] Element ${selector} loaded and validated`);
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

    function logSimplifiedHTML(element, itemSelector, maxDepth = 3) {
        function getElementSignature(el) {
            let sig = `<${el.tagName.toLowerCase()}`;
            if (el.id) sig += ` id="${el.id}"`;
            if (el.className) sig += ` class="${el.className}"`;
            sig += '>';
            return sig;
        }

        function buildTree(el, depth, indent = '') {
            if (depth > maxDepth) return [];

            const lines = [];
            const children = Array.from(el.children);
            const maxShow = 5;

            children.slice(0, maxShow).forEach(child => {
                const isMatch = itemSelector && child.matches(itemSelector);
                const prefix = isMatch ? '✓ ' : '  ';
                const suffix = isMatch ? ' [MATCH]' : '';
                lines.push(indent + prefix + getElementSignature(child) + suffix);

                if (depth < maxDepth) {
                    lines.push(...buildTree(child, depth + 1, indent + '  '));
                }
            });

            if (children.length > maxShow) {
                const remaining = children.length - maxShow;
                const remainingMatches = itemSelector
                    ? children.slice(maxShow).filter(c => c.matches(itemSelector))
                    : [];
                const matchInfo = remainingMatches.length > 0
                    ? ` (${remainingMatches.length} matches)`
                    : '';
                lines.push(indent + `  ... (${remaining} more${matchInfo})`);
            }

            return lines;
        }

        const output = [getElementSignature(element)];
        output.push(...buildTree(element, 1, '  '));

        console.log('[DEBUG] Container HTML structure:\n' + output.join('\n'));

        if (itemSelector) {
            const totalMatches = element.querySelectorAll(itemSelector).length;
            console.log(`[DEBUG] Total matches for "${itemSelector}": ${totalMatches}`);
        }
    }

    function addIndividualOverlays(containerSelector, itemSelector, config) {
        console.log(`[DEBUG] addIndividualOverlays called with:`, containerSelector, itemSelector, config);
        const container = $(containerSelector)[0];
        if (!container) {
            console.log(`[ERROR] Container ${containerSelector} not found`);
            return;
        }
        console.log(`[DEBUG] Container found:`, container);
        logSimplifiedHTML(container, itemSelector, 3);

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
        // Filter out items that have already been revealed
        const beforeRevealedFilter = allItems.length;
        allItems = allItems.filter(item => !item.classList.contains('revealed'));
        if (beforeRevealedFilter > allItems.length) {
            console.log(`[DEBUG] Filtered out ${beforeRevealedFilter - allItems.length} already-revealed items`);
        }
        if (allItems.length === 0) {
            console.log(`[ERROR] No ${itemName} found after filtering`);
            return;
        }

        console.log(`[DEBUG] Found ${allItems.length} ${itemName} to overlay`);

        // Apply blur effect if enabled - target child elements not the container
        if (blurEffect) {
            // Split comma-separated selectors and apply blur rules to each
            const selectors = itemSelector.split(',').map(s => s.trim());
            const blurTargets = ['#comment', 'img', 'h3', '#dismissible'];

            // Generate selectors for items that are NOT revealed (should be blurred)
            const notRevealedSelectors = selectors.flatMap(sel =>
                blurTargets.map(target => `${sel}:not(.revealed) ${target}`)
            ).join(',\n                ');

            // Generate selectors for revealed items (should NOT be blurred)
            const revealedSelectors = selectors.flatMap(sel =>
                blurTargets.map(target => `${sel}.revealed ${target}`)
            ).join(',\n                ');

            addGlobalStyle(`
                ${notRevealedSelectors} {
                    filter: blur(5px);
                    transition: filter 0.3s ease;
                }
                ${revealedSelectors} {
                    filter: none;
                }
                /* Ensure overlay stays sharp */
                .individual-item-overlay {
                    filter: none !important;
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
            revealButton.textContent = `Reveal this ${itemType} + ${adjacentRevealCount} below`;
            revealButton.style.cssText = `
                white-space: nowrap;
                background-color: #065fd4;
                color: white;
                border: none;
                border-radius: 4px;
                padding: 20px 30px;
                font-size: 16px;
                cursor: pointer;
                position: relative;
                z-index: 1;
            `;

            // Add pressAndHold behavior
            $(revealButton).pressAndHold({ holdTime: holdTime, allowFastForward: false });

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
                            // Always mark as revealed to prevent re-adding overlay
                            adjacentItem.classList.add('revealed');
                        }
                    }
                };

                removeAdjacentOverlays(currentIndex, 1, adjacentRevealCount);  // Remove below

                // Always mark as revealed to prevent re-adding overlay
                item.classList.add('revealed');

                console.log(`Revealed ${itemName} item at index ${currentIndex} and adjacent items`);
            });

            overlay.appendChild(revealButton);

            // Make sure the item has position relative
            const currentPosition = window.getComputedStyle(item).position;
            if (currentPosition === 'static') {
                item.style.position = 'relative';
            }

            console.log(`[DEBUG] Appending overlay to item:`, item);
            item.appendChild(overlay);
            console.log(`[DEBUG] Overlay appended. Item now has ${item.children.length} children`);
            console.log(`[DEBUG] Overlay computed styles:`, {
                display: overlay.style.display,
                position: overlay.style.position,
                zIndex: overlay.style.zIndex,
                width: overlay.offsetWidth,
                height: overlay.offsetHeight
            });
        });

        console.log(`[DEBUG] Added overlays to ${allItems.length} ${itemName}`);

        // Set up mutation observer for dynamically added items
        const observer = new MutationObserver(_.debounce(() => {
            console.log(`[DEBUG] Mutation detected in ${itemName} container`);
            let newItems = Array.from(container.querySelectorAll(itemSelector))
                .filter(item => !item.querySelector('.individual-item-overlay'))
                .filter(item => !item.classList.contains('revealed'));

            console.log(`[DEBUG] Found ${newItems.length} items without overlays (after filtering revealed items)`);

            if (filterFunction) {
                const beforeFilter = newItems.length;
                newItems = newItems.filter(filterFunction);
                console.log(`[DEBUG] Filtered from ${beforeFilter} to ${newItems.length} new items`);
            }

            if (newItems.length === 0) {
                console.log(`[DEBUG] No new ${itemName} to add overlays to`);
                return;
            }

            console.log(`[DEBUG] Adding overlays to ${newItems.length} new ${itemName}`);

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
                revealButton.textContent = `Reveal this ${itemType} + ${adjacentRevealCount} below`;
                revealButton.style.cssText = `
                    white-space: nowrap;
                    background-color: #065fd4;
                    color: white;
                    border: none;
                    border-radius: 4px;
                    padding: 20px 30px;
                    font-size: 16px;
                    cursor: pointer;
                    position: relative;
                    z-index: 1;
                `;

                $(revealButton).pressAndHold({ holdTime: holdTime, allowFastForward: false });

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
                                // Always mark as revealed to prevent re-adding overlay
                                adjacentItem.classList.add('revealed');
                            }
                        }
                    };

                    removeAdjacentOverlays(currentIndex, 1, adjacentRevealCount);

                    // Always mark as revealed to prevent re-adding overlay
                    item.classList.add('revealed');

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
                        // Wait for container to have matching items
                        const validation = (container) => {
                            const itemCount = container.querySelectorAll(overlayConfig.itemSelector).length;
                            console.log(`[DEBUG] Validation check - found ${itemCount} ${overlayConfig.itemSelector} in container`);
                            return itemCount > 0;
                        };
                        waitForElementToBeLoaded(overlayConfig.selector, () => {
                            console.log(`[DEBUG] Element loaded with items, calling addIndividualOverlays`);
                            addIndividualOverlays(overlayConfig.selector, overlayConfig.itemSelector, overlayConfig);
                        }, validation);
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
})(jQuery, window, document);
