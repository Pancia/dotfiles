// ==UserScript==
// @name     YTDL
// @version  4
// @require  http://code.jquery.com/jquery-latest.min.js
// @grant    none
// ==/UserScript==

function YTDL(downloadType) {
    function saveFile(filename, data) {
        var file = new Blob([data], {type: "text/plain"});
        var a = document.createElement("a"),
            url = URL.createObjectURL(file);
        a.href = url;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        setTimeout(function() {
            document.body.removeChild(a);
            window.URL.revokeObjectURL(url);
        }, 0);
    }
    const qp = new URLSearchParams(window.location.search);
    var fileName = (qp.get("list") && !qp.get("v")) ? qp.get("list")+".playlist" : qp.get("v")+".single"
    saveFile(fileName+`.${downloadType}.ytdl`, "ytdl gen, please ignore")
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

waitForElementToBeLoaded("ytd-mini-guide-renderer > #items", () => {
    $("ytd-mini-guide-renderer > #items")
        .after($(`<a id="endpoint" tabindex="-1" class="yt-simple-endpoint style-scope ytd-mini-guide-entry-renderer" title="Library" href="/playlist?list=WL"><span style="font-size:24px">🕓</span><span class="title style-scope ytd-mini-guide-entry-renderer">Watch Later</span></a>`))
})

waitForElementToBeLoaded(".ytd-masthead", () => {
    waitForElementToBeLoaded("#avatar-btn", () => {
        var $ytdl = $("<div>");
        $ytdl.append($("<span>ytdl(</span>")
            .css({"color": "red"
                , "font-size": "16px"}));
        $ytdl.append($("<a>🎵</a>")
            .css({"color": "red"
                , "font-size": "16px"
                , "cursor": "pointer"})
            .click(() => YTDL("audio")));
        $ytdl.append($("<span> | </span>")
            .css({"color": "red"
                , "font-size": "16px"}));
        $ytdl.append($("<a>📺</a>")
            .css({"color": "red"
                , "font-size": "16px"
                , "cursor": "pointer"})
            .click(() => YTDL("video")));
        $ytdl.append($("<span>)</span>")
            .css({"color": "red"
                , "font-size": "16px"}));
        $(".ytd-masthead > #end").before($ytdl);
    })
})
