// ==UserScript==
// @name anime watched tracker
// @version 0.1
// @require https://raw.githubusercontent.com/jashkenas/underscore/master/underscore.js
// ==/UserScript==

(function() {
  function addListItem(listName, item) {
    var list = JSON.parse(localStorage.getItem(listName) || "[]");
    list.push(item);
    localStorage.setItem(listName, JSON.stringify(_.uniq(list)));
  }

  const crossOutCSS = `
background: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' version='1.1' preserveAspectRatio='none' viewBox='0 0 100 100'><path d='M100 0 L0 100 ' stroke='white' stroke-width='3'/><path d='M0 0 L100 100 ' stroke='white' stroke-width='3'/></svg>");
background-repeat:no-repeat;
background-position:center center;
background-size: 100% 100%, auto;
`;
  const currentCSS = `
border: 2px solid red;
`;

  var onMutationsFinished = _.debounce((_) => {
    if (window.location.pathname.startsWith('/category')) {
      const target_ep = Number(new URLSearchParams(window.location.search).get("ep"));
      document.querySelectorAll("ul#episode_related a").forEach((a) => {
        ep = Number(a.children[0].innerText.match(/\d+/)[0]);
        if (ep < target_ep) {
          a.setAttribute("style", crossOutCSS);
        } else if (ep == target_ep) {
          a.setAttribute("style", currentCSS);
        }
      });
    } else {
      var button = document.createElement('button');
      button.innerHTML = 'watched';
      button.className = 'watched'
      button.addEventListener('click', function() {
        var url = window.location.href;
        fetch(`http://localhost:3145/tv-board/${url}`, {method: "post"});
        button.disabled = true;
      });
      if (! document.querySelector("button.watched")) {
        document.querySelector(".anime_video_body_episodes").appendChild(button);
      }
    }
  }, 100);
  var observer = new MutationObserver(onMutationsFinished);
  observer.observe(document, {subtree: true, childList: true});
})();
