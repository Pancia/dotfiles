local utils = require "utils"
local pretty = require "cc.pretty"
local mon = peripheral.find("monitor")
local function printScroll(title, t, loopRate)
    local w, h = mon.getSize()
    local lines, offsets = utils.formatText(w, t)
    local scrollOffset = 0
    local scrollProgress = 0
    local scrollProgressEnd = 9
    local extraLines = #lines - h - 1
    if extraLines <= 0 then
        mon.clear()
        mon.setCursorPos(1, 1)
        mon.write(title)
        for i,line in ipairs(lines) do
            mon.setCursorPos(1, i+1)
            mon.write(line)
        end
    else
        local function incScroll()
            scrollOffset = scrollOffset+offsets[math.fmod(scrollOffset+2, #offsets)+1]
            if scrollOffset > #lines then
                scrollOffset = math.fmod(scrollOffset, #lines)
            end
        end
        local function decScroll()
            scrollOffset = scrollOffset-1
            if scrollOffset < 0 then
                scrollOffset = #lines-1
            end
        end
        local function loopSleep()
            sleep(loopRate)
            scrollProgress = scrollProgress+1
            if scrollProgress > scrollProgressEnd then
                scrollProgress = 0
                incScroll()
            end
        end
        local function monitorTouch()
            event, side, x, y = os.pullEvent("monitor_touch")
            if y == h and (x >= 1 and x <= 4) then
                scrollProgress = 0
                incScroll()
            elseif y == h and (x >= 6 and x <= 7) then
                scrollProgress = 0
                decScroll()
            end
        end
        while true do
            mon.clear()
            mon.setCursorPos(1, 1)
            mon.write(title)
            mon.setCursorPos(1, h)
            mon.write(string.format("DOWN UP LOOP t[%s/%s] s[%s/%s->%s]", scrollProgress, scrollProgressEnd, scrollOffset, #lines, offsets[math.fmod(scrollOffset+2, #offsets)+1]))
            local monLineIdx
            for monLineIdx=2,h-1 do
                if #lines >= scrollOffset then
                    mon.setCursorPos(1, monLineIdx)
                    mon.write(lines[math.fmod(monLineIdx+scrollOffset, #lines)+1])
                end
            end
            parallel.waitForAny(loopSleep, monitorTouch)
        end
    end
end

function getBlock(blockID)
    print("getBlock "..blockID)
    return http.get("http://192.168.0.100:31415/logseq/block?id="..blockID).readAll()
end

function getPage(pageID)
    print("getPage "..pageID)
    return http.get("http://192.168.0.100:31415/logseq/page?id="..pageID).readAll()
end

function runQuery(query)
    print("runQuery "..query)
    return http.get("http://192.168.0.100:31415/logseq/query?query="..utils.urlencode(query)).readAll()
end

function runDatascript(query)
    print("runDatascript "..query)
    return http.get("http://192.168.0.100:31415/logseq/datascript?query="..utils.urlencode(query)).readAll()
end

print("LOGSEQ v6")
args = {...}
command = args[1]
arg = args[2]
textScale = tonumber(args[3]) or 0.5
mon.setTextScale(textScale)
loopRate = tonumber(args[4]) or 0.5

if command == "block" then
    content = getBlock(arg)
    title = "block "..arg
elseif command == "page" then
    content = getPage(arg)
    title = "page "..arg
elseif command == "query" then
    content = runQuery(arg)
    title = "query "..arg
elseif command == "datascript" then
    content = runDatascript(arg)
    title = "datascript "..arg
else
    print("INVALID COMMAND TYPE")
    return
end

lines = {}
for s in content:gmatch("[^\r\n]+") do
    table.insert(lines, s)
end

printScroll(title, lines, loopRate)
