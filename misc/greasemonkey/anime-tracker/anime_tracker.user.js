// ==UserScript==
// @name anime watched tracker
// @version 3
// @require https://raw.githubusercontent.com/jashkenas/underscore/master/underscore.js
// ==/UserScript==

(function() {
    let host = 'http://localhost:3142'
    async function send(url, onSuccess) {
        let response = await fetch(`${host}/${url}`, {
            method: "post"
        }).catch(function(err) {
            console.error('Fetch Error', err, 'response', response)
            alert(`Fetch error, check the console!`)
        })
        if (!response.ok) {
            console.error('Fetch Error', response)
            alert(`Fetch error: ${response.status}. Check the console!`)
        } else {
            onSuccess(response)
        }
    }
    var onMutationsFinished = _.debounce((_) => {
        if (! document.querySelector("button.watched") && document.querySelector(".anime_video_body_episodes")) {
            var button = document.createElement('button')
            button.style = 'float: right;'
            button.innerHTML = 'watched'
            button.className = 'watched'
            button.addEventListener('click', function() {
                var url = window.location.href
                send(`/tv-board/watch/${url}`, (res) => {
                    button.disabled = true
                })
            })
            document.querySelector(".anime_video_body_episodes").appendChild(button)
        }
        if (location.pathname.match("/category") && ! document.querySelector("button.follow")) {
            var button = document.createElement('button')
            button.innerHTML = 'follow'
            button.className = 'follow'
            button.addEventListener('click', async function() {
                var url = window.location.href
                let img = document.querySelector(".anime_info_body_bg img").src
                send(`/tv-board/follow/${url}?img=${img}`, (res) => {
                    button.disabled = true
                })
            })
            document.querySelector(".anime_info_episodes").append(button)
        }
    }, 100)
    var observer = new MutationObserver(onMutationsFinished)
    observer.observe(document, {subtree: true, childList: true})
})()
