(function() {
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
    var fileName = (!qp.get("v") && qp.get("list")) ? qp.get("list")+".playlist" : qp.get("v")+".video";
    saveFile(fileName+".ytdl", "ytdl gen, please ignore")
})();
