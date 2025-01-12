// ==UserScript==
// @name     Overlays
// @version  34
// @require  http://code.jquery.com/jquery-latest.min.js
// @require  https://cdn.jsdelivr.net/npm/js-cookie@3.0.1/dist/js.cookie.min.js
// @require  https://raw.githubusercontent.com/jashkenas/underscore/master/underscore.js
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

    var pressAndHold = "pressAndHold",
        defaults = {
            holdTime: 700,
            progressIndicatorRemoveDelay: 300,
            progressIndicatorColor: "#ff0000",
            progressIndicatorOpacity: 0.6

        };

    function Plugin(element, options) {
        this.element = element;
        this.settings = $.extend({}, defaults, options);
        this._defaults = defaults;
        this._name = pressAndHold;
        this.init();
    }

    Plugin.prototype = {
        init: function() {
            var _this = this,
                timer,
                decaCounter,
                isActive = false,
                progressIndicatorHTML;


            $(this.element).css({
                display: 'block',
                overflow: 'hidden',
                position: 'relative'
            });

            progressIndicatorHTML = '<div class="holdButtonProgress" style="height: 100%; width: 100%; position: absolute; top: 0; left: -100%; background-color:' + this.settings.progressIndicatorColor + '; opacity:' + this.settings.progressIndicatorOpacity + ';"></div>';

            $(this.element).prepend(progressIndicatorHTML);

            $(this.element).mousedown(function(e) {
                if(e.button == 2) { return; }
                if(isActive) {
                    decaCounter += 100;
                } else {
                    $(_this.element).trigger('start.pressAndHold');
                    isActive = true;
                    decaCounter = 0;
                    timer = setInterval(function() {
                        decaCounter += 10;
                        $(_this.element).find(".holdButtonProgress").css("left", ((decaCounter / _this.settings.holdTime) * 100 - 100) + "%");
                        if (decaCounter >= _this.settings.holdTime) {
                            isActive = false;
                            _this.exitTimer(timer);
                            $(_this.element).trigger('complete.pressAndHold');
                        }
                    }, 10);
                    $(_this.element).on('mouseleave.pressAndHold', function(event) {
                        isActive = false;
                        _this.exitTimer(timer);
                    });

                }
            });
        },
        exitTimer: function(timer) {
            var _this = this;
            clearTimeout(timer);
            $(this.element).off('mouseleave.pressAndHold');
            setTimeout(function() {
                $(".holdButtonProgress").css("left", "-100%");
                $(_this.element).trigger('end.pressAndHold');
            }, this.settings.progressIndicatorRemoveDelay);
        }
    };

    $.fn[pressAndHold] = function(options) {
        return this.each(function() {
            if (!$.data(this, "plugin_" + pressAndHold)) {
                $.data(this, "plugin_" + pressAndHold, new Plugin(this, options));
            }
        });
    };

})(jQuery, window, document);

(function($) {
    var video_overlay_image_url = "https://cdnb.artstation.com/p/assets/images/images/005/165/059/large/nise-stars-talk-through-me-by-dniseb-sml.jpg";
    var home_row_overlay_image_url = "https://images-wixmp-ed30a86b8c4ca887773594c2.wixmp.com/f/0a9c9fab-87f0-4659-a31b-e1e930c397c7/dewsf9j-bbcc145e-fe1e-47fb-98e9-c45e86c9902a.jpg?token=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1cm46YXBwOjdlMGQxODg5ODIyNjQzNzNhNWYwZDQxNWVhMGQyNmUwIiwiaXNzIjoidXJuOmFwcDo3ZTBkMTg4OTgyMjY0MzczYTVmMGQ0MTVlYTBkMjZlMCIsIm9iaiI6W1t7InBhdGgiOiJcL2ZcLzBhOWM5ZmFiLTg3ZjAtNDY1OS1hMzFiLWUxZTkzMGMzOTdjN1wvZGV3c2Y5ai1iYmNjMTQ1ZS1mZTFlLTQ3ZmItOThlOS1jNDVlODZjOTkwMmEuanBnIn1dXSwiYXVkIjpbInVybjpzZXJ2aWNlOmZpbGUuZG93bmxvYWQiXX0.32YU-FSqVyRlTsY4YKyBo3IAo5IqIQVTgNudrneYyFY";

    function isEnabledForUser() {
        var now = Date.now();
        var isEnabled = Cookies.get("overlays:isDisabled") != "true";
        var disabledUntil = Cookies.get("overlays:disabledUntil") || 0;
        if (now > disabledUntil) { Cookies.remove("overlays:disabledUntil"); }
        //console.log(`isE ${isEnabled} now ${now} ?> ${now > disabledUntil} until ${disabledUntil}`);
        return isEnabled && now > disabledUntil;
    }

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

    function MAIN() {
        if (window.location.host == "www.youtube.com") {
            if (window.location.pathname.match(/^\/embed/)) { return }
            addGlobalStyle('#contents { filter: grayscale(1); }'); // greyscale everything except the video
            if ($("#overlay-delay")[0] == null) {
                var disabledUntil = Cookies.get("overlays:disabledUntil")
                var $delay = $(`<button id='overlay-delay'>⏰: ${(disabledUntil && displayTime(disabledUntil)) || "0"}</button>`)
                    .pressAndHold({holdTime: 30000})
                    .on("complete.pressAndHold", () => {
                        var until = Date.now() + 1000*60*5;
                        Cookies.set("overlays:disabledUntil", until);
                        $delay.text(`⏰: ${displayTime(until)}`);
                        document.querySelectorAll('.yt-row-overlay').forEach((i) => {i.remove()});
                    });
                //$(".ytd-masthead > #end").before($delay);
            }

            if (Cookies.get("overlays:isDisabled") == null) {
                var shouldDisable = confirm("Disable for this session?");
                Cookies.set("overlays:isDisabled", shouldDisable);
            }
            if (window.location.pathname == "/watch") {
                waitForElementToBeLoaded("#comments #comment", () => {
                    addOverlay("#comments", "STOP! is it really worth it?", 10000);
                });
                waitForElementToBeLoaded("#related #items", () => {
                    addOverlay("#related", "related videos", 10000);
                });
            }
            if (isEnabledForUser()) {
                if (window.location.pathname == "/watch") {
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
                                    'background-image': "url('"+video_overlay_image_url+"')"
                                });
                            var opts = {holdTime: 10000, progressIndicatorColor: "#ff00ff", progressIndicatorOpacity: 0.2};
                            addOverlayTo("#movie_player", "player_overlay", button, opts);
                            var timerID = setInterval(() => {
                                if ($("#player_overlay")[0] != null) {
                                    document.querySelector("video").pause();
                                } else {
                                    clearInterval(timerID);
                                }
                            }, 1000);
                            setInterval(() => {
                                if ($("video")[0].playbackRate > 1.0) {
                                    $("video")[0].playbackRate = 1.0;
                                    alert("You told yourself to be more aware and present while you watched youtube.\nSlow is Smooth, Smooth is Fast.");
                                }
                            }, 1000);
                        });
                    });
                }
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
                        var $overlay = $(`<div class='yt-row-overlay' id='yt-row-${idx}'></div>`)
                            .width($(row).width())
                            .css({
                                'opacity' : 1,
                                'position': 'absolute',
                                'background-color': 'black',
                                'height': '100%',
                                'z-index': 2200
                            });
                        var required_pattern = "please show me this row of suggested videos";
                        var $form = $(`<form>`);
                        $form.append($(`<input style='position:absolute; z-index: 2350; width: 100%; opacity: 0.5;'/>`));
                        $form.append($(`<input placeholder="${required_pattern}" style='z-index: 2300; position: absolute; width: 100%; opacity: 1.0;' />`));
                        $form.append($(`<input type="submit" style="display: none" />`));
                        $form.on('submit', function(e) {
                            if (e.target.children[0].value !== required_pattern) {
                                alert("INVALID");
                            } else {
                                try{ row.setAttribute("data-overlay", "disabled"); }catch(e){}
                                $(`[id='yt-row-${idx}']`).remove();
                                $(`[id='yt-row-${idx+1}'] input`).trigger("focus");
                            }
                            return false;
                        });
                        $form.appendTo($overlay);
                        var $img = $('<div>').css({
                            'height': '100%',
                            'width': '100%',
                            'z-index': 2250,
                            'background-size': 'contain',
                            'background-image': `url('${home_row_overlay_image_url}')`,
                            'transform': `scale(${idx % 2 == 0 ? 1 : -1}, 1)`
                        }).pressAndHold({holdTime: row.children.length * 2000}).on("complete.pressAndHold", () => {
                            try{ row.setAttribute("data-overlay", "disabled"); }catch(e){}
                            $(`[id='yt-row-${idx}']`).remove();
                        }).appendTo($overlay);
                        $img.attr("data-is-overlay", true);
                        $img.appendTo($overlay);
                        $overlay.prependTo(row);
                        row.setAttribute("data-overlay", "initialized");
                    }
                });
            }
        }
    }, 100);
    var observer = new MutationObserver(onMutationsFinished);
    observer.observe(document, {subtree: true, childList: true});
})(jQuery);
