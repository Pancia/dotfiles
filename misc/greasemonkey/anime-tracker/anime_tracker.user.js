// ==UserScript==
// @name anime watched tracker
// @version 6
// @require https://raw.githubusercontent.com/jashkenas/underscore/master/underscore.js
// ==/UserScript==

(function() {
    let host = 'http://192.168.0.100:3142'
    var onMutationsFinished = _.debounce((_) => {
        if (document.querySelector("iframe.anime_tracker")) {
            return
        }
        var iframe = document.createElement('iframe')
        iframe.className = 'anime_tracker'
        iframe.width = 81
        iframe.height = 42
        iframe.style = 'float: right;'
        if (document.querySelector(".anime_video_body_episodes")) {
            iframe.src = host + `/tracker.html?kind=watch&url=${window.location.href}`
            document.querySelector(".anime_video_body_episodes").appendChild(iframe)
        } else if (location.pathname.match("/category")) {
            let img = document.querySelector(".anime_info_body_bg img").src
            iframe.src = host + `/tracker.html?kind=follow&url=${window.location.href}&img=${img}`
            document.querySelector(".anime_info_episodes").appendChild(iframe)
        }
    }, 100)
    var observer = new MutationObserver(onMutationsFinished)
    observer.observe(document, {subtree: true, childList: true})
})()
