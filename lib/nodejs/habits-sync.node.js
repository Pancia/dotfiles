const http = require('http');
const fs = require('fs');
const os = require('os');
const url = require('url');
const qs = require('querystring');

http.createServer(function(req, res) {
    if (req.url.startsWith('/habits-sync') && req.method == 'POST') {
        console.log(new Date());
        const filename = qs.parse(url.parse(req.url).search.slice(1)).name;
        console.log(`INCOMING: ${filename}`);
        var out = fs.createWriteStream('extra.tmp.zip');
        req.on('data', function(data) {
            console.log(`receiving: ${data.length} bytes`);
            out.write(data);
        })
        req.on('end', function(data) {
            console.log("end of request data");
            console.log(`writing to '${os.homedir()}/Dropbox/habits/${filename}'`);
            fs.copyFileSync("extra.tmp.zip", `${os.homedir()}/Dropbox/habits/${filename}`);
            console.log();
            res.writeHead(200);
            res.end('Received!');
            process.exit(0);
        })
    } else {
        res.writeHead(404);
        res.end('Nothing Here!');
    }
}).listen(7777);
console.log("listening on port 7777 for '/habits-sync'");
console.log("will export to '~/Dropbox/habits/*'");
