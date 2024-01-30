// ==UserScript==
// @name     Inbox Logseq PARA
// @version  3
// @grant    GM.registerMenuCommand
// @require  https://cdnjs.cloudflare.com/ajax/libs/readability/0.5.0/Readability.js
// @require  https://unpkg.com/turndown/dist/turndown.js
// @require  http://code.jquery.com/jquery-latest.min.js
// ==/UserScript==

(function($, window, document) {

    function createModal() {
        // Create the modal overlay
        var overlay = $('<div>').attr({
            id: 'overlay',
            'data-overlay': true
        }).css({
            display: 'none',
            position: 'fixed',
            top: 0,
            left: 0,
            width: '100%',
            height: '100%',
            backgroundColor: 'rgba(0, 0, 0, 0.5)',
            zIndex: 99998
        });

        // Create the modal content
        var modalContent = $('<div>').attr({
            id: 'modalContent',
            'data-overlay': true
        }).css({
            display: 'none',
            backgroundColor: '#fefefe',
            padding: '20px',
            borderRadius: '8px',
            position: 'fixed',
            top: '50%',
            left: '50%',
            transform: 'translate(-50%, -50%)',
            width: '90%',
            height: '90%',
            zIndex: 99999,
            fontSize: '30px'
        });

        var textInputContainer = $('<div>').css({
            display: 'flex',
            flexDirection: 'row',
            height: '90%'
        });

        var textInput = $('<textarea>').attr({
            id: 'textInput'
        }).css({
            flex: '3',
            fontSize: '29px'
        });
        var para = $('<textarea>').attr({
            id: 'sidebar'
        }).css({
            flex: '2',
            fontSize: '21px'
        });

        textInputContainer.append(textInput, para);

        // Create the submit button
        var submitButton = $('<button>').text('Submit').css({
            fontSize: '30px'
        }).click(submitText);

        // Append elements to modal content
        if (window.location.host == 'www.youtube.com') {
            let chan = $('ytd-channel-name a').text();
            modalContent.append(chan, $('<br>'));
        }
        modalContent.append(textInputContainer, submitButton);

        // Append modal content to the document body
        $('body').append(overlay, modalContent);
    }

    function today() {
        date = new Date()
        return `${date.getFullYear()}_${padZero(date.getMonth() + 1)}_${padZero(date.getDate())}`
    }

    function getPageURL() {
        if (window.location.host == 'www.youtube.com') {
            let url = new URL(window.location.href);
            const allowedParams = ["v"];
            const queryParams = url.searchParams;
            for (const key of Array.from(queryParams.keys())) {
                console.log('key:', key)
                if (!allowedParams.includes(key)) {
                    queryParams.delete(key);
                }
            }
            console.log('url:'+url, queryParams)
            return url.toString();
        } else {
            return window.location.href
        }
    }

    // Function to open the modal
    async function openModal() {
        document.querySelector('#overlay').style.display = 'block';
        document.querySelector('#modalContent').style.display = 'block';
        template = `
note/source:: [[note/source/HERE]]
note/author:: [[note/author/HERE]]
note/link:: ${getPageURL()}
note/date:: [[${today()}]]
note/para:: [[para/HERE]]

- {{embed [[note/summary/v1]]}}
    - LATER [[note/summary/v1]] #note/summary
- {{embed [[note/context/internalv1]]}}
    - LATER [[note/context/internal/v1]] #note/context
- {{embed [[note/context/external/v1]]}}
    - LATER [[note/context/externalv1]] #note/context
- {{embed [[note/context/social/v1]]}}
    - LATER [[note/context/social/v1]] #note/context
- {{embed [[note/context/current-status/v1]]}}
    - LATER [[note/context/current-status/v1]] #note/context
`.trim()
        document.querySelector('#textInput').textContent = template
        let response = await(await fetch(`${host}/getPARA`)).text()
        document.querySelector('#sidebar').textContent = response
    }

    function closeModal() {
        document.querySelector('#overlay').style.display = 'none'
        document.querySelector('#modalContent').style.display = 'none'
    }

    let host = 'http://192.168.0.100:3579'

    async function send(url, body, onSuccess) {
        let response = await fetch(`${host}/${url}`, {
            method: "post", body: JSON.stringify(body)
        }).catch(function(err) {
            console.error('Fetch Error', err)
            alert(`Fetch error, check the console!`)
        })
        if (!response.ok) {
            console.error('Fetch Error', response)
            alert(`Fetch error: ${response.status}. Check the console!`)
        } else {
            onSuccess(response)
        }
    }

    function pageToMarkdown() {
        let content = new Readability(document.cloneNode(true)).parse()
        console.log(content)
        var turndownService = new TurndownService()
        turndownService.remove('form')
        turndownService.remove((node, options) => {
            return node.getAttribute('data-overlay')
        })
        var markdown = turndownService.turndown(content.content)
        return markdown
    }

    function getBeginAndEnd(inputString, x, y) {
        const lines = inputString.split('\n');
        const firstXLines = lines.slice(0, x);
        const lastYLines = lines.slice(-y);
        return firstXLines.join('\n') + '\n......\n' + lastYLines.join('\n')
    }

    function submitText() {
        var textValue = document.querySelector('#textInput').value;
        console.log("Submitted text:", textValue);
        let markdown = pageToMarkdown()
        let body = {
            note: textValue,
            url: getPageURL(),
            title: document.title,
            date: today(),
            pageContent: markdown
        }
        send("saveNotes", body, async (response) => {
            alert(getBeginAndEnd(await response.text(), 15, 6));
            if (confirm("Accept?")) {
                send("moveNote", {title: document.title}, (r) => {})
            };
        })
        closeModal();
    }

    function padZero(number) {
        return number < 10 ? `0${number}` : number;
    }

    function showContent() {
        if (window.location.host != 'www.youtube.com') {
            var markdown = pageToMarkdown()
            alert(getBeginAndEnd(markdown, 6, 6))
        }
    }

    function saveNotes() {
        createModal()
        openModal()
    }

    function main() {
        if (window.top != window.self) {
            return
        }
        GM.registerMenuCommand("SAVE NOTES", saveNotes)
    }

    main()
})(jQuery, window, document);

