// ==UserScript==
// @name     Google It
// @version  1
// @grant    none
// @require  http://code.jquery.com/jquery-latest.min.js
// ==/UserScript==

function waitForElementToBeLoaded(selector, callback) {
    var tid = setInterval(function() {
        // wait for x element to have been loaded, ie: not null
        var x = $(selector)[0]
        if (x == null) { return }
        // x was loaded, go ahead!
        clearInterval(tid)
        callback(x)
    }, 100);
}

waitForElementToBeLoaded(".search-filters", () => {
    const q = new URLSearchParams(window.location.search).get('q')
    const href = "https://google.com/search?q="
    $("<a>Google It</a>")
        .attr({href: `${href}${encodeURIComponent(q)}`,
            rel: "noopener nofollow noreferrer"})
        .appendTo(".search-filters")
})
