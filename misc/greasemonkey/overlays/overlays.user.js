// ==UserScript==
// @name     Overlays
// @version  23
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
      console.log("addOverlayTo", overlayID);
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
    function MAIN() {
        if (window.location.host == "www.youtube.com") {
            // greyscale everything except the video
            addGlobalStyle('#contents { filter: grayscale(1); }');
            if (window.location.pathname == "/watch") {
                waitForElementToBeLoaded("#comments #comment", () => {
                    addOverlay("#comments", "STOP! is it really worth it?");
                });
                waitForElementToBeLoaded("#related #items", () => {
                    addOverlay("#related");
                });
                waitForElementToBeLoaded("#movie_player", () => {
                    var button = $('<button>')
                        .html($('<span />')
                            .css({'background-color': '#fff5'})
                            .html('Are you sure you should be watching this?'))
                        .css({
                            'height': '100%',
                            'width': '100%',
                            'background-size': 'cover',
                            'background-image': "url('https://cdn.donmai.us/original/f0/49/__amano_nene_production_kawaii_drawn_by_oreazu__f04956b57e752aec17c9b4cb07449c28.jpg')"
                        });
                    var opts = {holdTime: 3000, progressIndicatorColor: "#ff00ff", progressIndicatorOpacity: 0.3};
                    addOverlayTo("#movie_player", "player_overlay", button, opts);
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
        if (window.location.host == "www.youtube.com" && window.location.pathname == "/") {
          Array.from(document.querySelectorAll("#contents.ytd-rich-grid-row")).forEach((row, idx) => {
                if (!row.getAttribute("data-overlay")) {
                    var button = $('<button>').css({
                        'height': '100%',
                        'width': '100%',
                        'background-size': 'contain',
                        'background-image': "url('https://cdn.donmai.us/original/a8/b9/__amano_nene_production_kawaii_drawn_by_yukiunag1__a8b9ff28553daa1ac80889e4d8880773.jpg')"

                    });
                    var opts = {holdTime: 3000};
                    addOverlayTo(row, `yt-row-${idx}`, button, opts);
                    row.setAttribute("data-overlay", "initialized");
                }
            });
        }
    }, 222);
})(jQuery);

