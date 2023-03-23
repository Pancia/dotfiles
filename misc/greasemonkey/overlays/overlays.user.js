// ==UserScript==
// @name     Overlays
// @version  29
// @require  http://code.jquery.com/jquery-latest.min.js
// @require  https://raw.githubusercontent.com/santhony7/pressAndHold/master/jquery.pressAndHold.js
// @require  https://cdn.jsdelivr.net/npm/js-cookie@3.0.1/dist/js.cookie.min.js
// @require  https://raw.githubusercontent.com/jashkenas/underscore/master/underscore.js
// @grant    none
// ==/UserScript==

(function($) {
    var video_overlay_image_url = "https://cdnb.artstation.com/p/assets/images/images/005/165/059/large/nise-stars-talk-through-me-by-dniseb-sml.jpg";
    var home_row_overlay_image_url = "https://cdn.donmai.us/original/a8/b9/__amano_nene_production_kawaii_drawn_by_yukiunag1__a8b9ff28553daa1ac80889e4d8880773.jpg";

    function isEnabledForUser() {
      return Cookies.get("overlays:isDisabled") != "true";
    }

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
            if (Cookies.get("overlays:isDisabled") == null) {
                var shouldDisable = confirm("Disable for this session?");
                Cookies.set("overlays:isDisabled", shouldDisable);
            }
            if (window.location.pathname == "/watch") {
                waitForElementToBeLoaded("#comments #comment", () => {
                    addOverlay("#comments", "STOP! is it really worth it?");
                });
                waitForElementToBeLoaded("#related #items", () => {
                    addOverlay("#related");
                });
            }
            if (isEnabledForUser()) {
                addGlobalStyle('#contents { filter: grayscale(1); }'); // greyscale everything except the video
                waitForElementToBeLoaded("#movie_player", () => {
                    waitForElementToBeLoaded("video", () => {
                        document.querySelectorAll('#player_overlay').forEach((i) => {i.remove()});
                        var button = $('<button>')
                            .html($('<span />')
                                .css({'background-color': '#fff5', 'position': 'absolute', 'bottom': '22px', 'left': '38%'})
                                .html('Are you sure you should be watching this?'))
                            .css({
                                'height': '100%',
                                'width': '100%',
                                'background-size': 'cover',
                                'background-image': "url('"+video_image_overlay+"')"
                            });
                        var opts = {holdTime: 3000, progressIndicatorColor: "#ff00ff", progressIndicatorOpacity: 0.3};
                        addOverlayTo("#movie_player", "player_overlay", button, opts);
                        document.querySelector("video").pause();
                    });
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

    var onMutationsFinished = _.debounce((_) => {
        if (this.lastUrl !== location.href || ! this.lastUrl) {
            this.lastUrl = location.href;
            MAIN();
        }
        if (window.location.host == "www.youtube.com" && window.location.pathname == "/") {
            if (isEnabledForUser()) {
                Array.from(document.querySelectorAll("#contents.ytd-rich-grid-row")).forEach((row, idx) => {
                    if (row.getAttribute("data-overlay") != "disabled" && !row.querySelector("[data-is-overlay]")) {
                        var button = $('<button>').css({
                            'height': '100%',
                            'width': '100%',
                            'background-size': 'contain',
                            'background-image': "url('"+home_row_overlay_image_url+"')"
                        });
                        button.attr("data-is-overlay", true);
                        var opts = {holdTime: row.children.length * 1000};
                        addOverlayTo(row, `yt-row-${idx}`, button, opts);
                        row.setAttribute("data-overlay", "initialized");
                    }
                });
            }
        }
    }, 100);
    var observer = new MutationObserver(onMutationsFinished);
    observer.observe(document, {subtree: true, childList: true});
})(jQuery);

