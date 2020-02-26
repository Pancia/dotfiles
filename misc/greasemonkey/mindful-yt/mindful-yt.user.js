// ==UserScript==
// @name     mindful-yt
// @version  1
// @require  http://code.jquery.com/jquery-latest.min.js
// @grant    none
// ==/UserScript==

/*\
 * BEGIN CONFIG:
\*/

var mindfulnessReminderText = `
<p>PLACEHOLDER REMINDER TEXT</p>
<p>PLEASE EDIT SCRIPT CONFIG</p>
`;
var dismissWaitTime = 5; // seconds

/*\
 * END OF CONFIG
<*===========================================================*>
 * BEGIN CODE:
 *
 * NOTE: https://bugzilla.mozilla.org/show_bug.cgi?id=1591674
 *  firefox:
 *      set gfx.webrender.all = true
 *      set layout.css.backdrop-filter.enabled = true
\*/

function addGlobalStyle(css) {
    var head, style;
    head = document.getElementsByTagName("head")[0];
    if (!head) { return; }
    style = document.createElement("style");
    style.type = "text/css";
    style.innerHTML = css;
    style.title = "mindful-yt";
    head.appendChild(style);
}

addGlobalStyle(`
#mindful-yt-overlay {
    display: grid;
    grid-template-areas:
    '. .        .'
    '. text     .'
    '. dismiss  .'
    '. .        .';
    grid-template-columns: 1fr 2fr 1fr;
    grid-template-rows: 2fr 1fr 1fr 2fr;
    grid-gap: 10px 10px;
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background-color: rgba(128,128,128,.8);
    z-index: 100000;
    color: #fff;
    cursor: wait;
}
.mindful-yt-text-area {
    grid-area: text;
    place-self: end center;
}
.mindful-yt-dismiss-area {
    grid-area: dismiss;
    place-self: start center;
}
.mindful-yt-reminder {
    font-size: 36px;
    color: gold;
}
.mindful-yt-dismiss {
    cursor: wait;
    font-size: 18px;
}
.mindful-yt-blur {
    backdrop-filter: blur(3px);
}
`)

function showOverlay(text, selector) {
    var overlayHtml = `
<div id='mindful-yt-overlay' class='mindful-yt-blur'>
    <div class='mindful-yt-text-area'>
        <h1 class='mindful-yt-reminder'>
            ${text}
        </h1>
    </div>
    <button
        id='mindful-yt-dismiss'
        class='mindful-yt-dismiss-area mindful-yt-dismiss'>
      Loading...
    </button>
</div>
`;
    $(overlayHtml).appendTo(selector);
}

var dismissWaitTimer;

function MAIN() {
    clearTimeout(dismissWaitTimer);
    var waitFor = dismissWaitTime;

    showOverlay(mindfulnessReminderText, "body");
    dismissWaitTimer = setInterval(() => {
        $("#mindful-yt-dismiss").text(`Wait ${waitFor}s`);
        if (waitFor-- == 0) {
            $("#mindful-yt-dismiss")
                .text(`DISMISS`)
                .click(() => {$("#mindful-yt-overlay").remove();});
            $("#mindful-yt-overlay").css({
                "cursor": "auto"
            });
            $("#mindful-yt-dismiss").css({
                "cursor": "auto"
            });
            clearTimeout(dismissWaitTimer);
        }
    }, 1000);
}

var pageURLCheckTimer = setInterval(function() {
    if (this.lastUrl !== location.href || ! this.lastUrl) {
        this.lastUrl = location.href;
        MAIN();
    }
}, 222);

