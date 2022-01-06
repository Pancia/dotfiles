// ==UserScript==
// @name     Overlays
// @version  14
// @require  http://code.jquery.com/jquery-latest.min.js
// @require  https://raw.githubusercontent.com/santhony7/pressAndHold/master/jquery.pressAndHold.js
// @grant    none
// ==/UserScript==

(function($) {
    function addOverlay(selector, text) {
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
        }).pressAndHold({holdTime: 3000}).on("complete.pressAndHold", () => {
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

    function MAIN() {
        if (window.location.host == "www.youtube.com") {
            if (window.location.pathname == "/watch") {
                waitForElementToBeLoaded("#comments #comment", () => {
                    addOverlay("#comments", "STOP! is it really worth it?");
                });
                waitForElementToBeLoaded("#related #items", () => {
                    addOverlay("#related");
                });
            }
        }

        if (window.location.host == "www.linkedin.com") {
            waitForElementToBeLoaded(".news-module", () => {
                addOverlay(".news-module");
            });
            if (window.location.pathname == "/feed/") {
                waitForElementToBeLoaded("#main", () => {
                    addOverlay("#main");
                });
            }
            if (window.location.pathname == "/notifications/") {
                waitForElementToBeLoaded("#main", () => {
                    addOverlay("#main");
                });
            }
            if (window.location.pathname.startsWith("/news/daily-rundown/")) {
                waitForElementToBeLoaded("#main", () => {
                    addOverlay("#main");
                });
            }
        }
    }

    var pageURLCheckTimer = setInterval(function() {
        if (this.lastUrl !== location.href || ! this.lastUrl) {
            this.lastUrl = location.href;
            MAIN();
        }
    }, 222);
})(jQuery);
