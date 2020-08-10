// ==UserScript==
// @name     YTDL
// @version  2
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

waitForElementToBeLoaded(".ytd-masthead", () => {
    waitForElementToBeLoaded("#avatar-btn", () => {
        $(".ytd-masthead > #end")
            .before(
                $("<a>ytdl(AUDIO)</a>")
                .css({"color": "red"
                    , "font-size": "16px"
                    , "cursor": "pointer"})
                .click(() => YTDL("audio")))
            .before(
                $("<a>ytdl(VIDEO)</a>")
                .css({"color": "red"
                    , "font-size": "16px"
                    , "cursor": "pointer"})
                .click(() => YTDL("video")))
    })
})
