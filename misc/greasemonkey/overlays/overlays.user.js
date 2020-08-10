// ==UserScript==
// @name     Overlays
// @version  1
// @require  http://code.jquery.com/jquery-latest.min.js
// @grant    none
// ==/UserScript==

function addOverlay(selector) {
    var $overlay = $(`<div id='${selector}'></div>`)
        .width($(selector).width())
        .css({
            'opacity' : 1,
            'position': 'absolute',
            'background-color': 'black',
            'height': '100%',
            'z-index': 5000
        });
    $('<button>', {
        'text': `Show: ${selector}`,
        'click': (e) => {$(`[id='${selector}']`).remove()}
    }).css({
        'height': '50px',
        'background-color': 'white'
    }).appendTo($overlay);

    $overlay.prependTo(selector)
}

function waitForElementToBeLoaded(selector, callback) {
    var tid = setInterval(function() {
        // wait for x element to have been loaded, ie: not null
        var x = $(selector)[0]
        if (x == null) { return }
        // x was loaded, go ahead!
        clearInterval(tid)
        callback()
    }, 100);
}

function MAIN() {
    if (window.location.host == "www.youtube.com") {
        waitForElementToBeLoaded("#comments #comment", () => {
            addOverlay("#comments");
        });
        waitForElementToBeLoaded("#related #dismissable", () => {
            addOverlay("#related");
        });
        waitForElementToBeLoaded("#primary", () => {
            addOverlay("#primary");
        });
    }

    if (window.location.host == "www.linkedin.com") {
        waitForElementToBeLoaded(".feed-shared-news-module", () => {
            addOverlay(".feed-shared-news-module");
        });
        if (window.location.pathname == "/feed/") {
            waitForElementToBeLoaded(".core-rail", () => {
                addOverlay(".core-rail");
            });
        }
        if (window.location.pathname == "/notifications/") {
            waitForElementToBeLoaded(".core-rail", () => {
                addOverlay(".core-rail");
            });
        }
        if (window.location.pathname.startsWith("/news/daily-rundown/")) {
            waitForElementToBeLoaded(".core-rail", () => {
                addOverlay(".core-rail");
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
