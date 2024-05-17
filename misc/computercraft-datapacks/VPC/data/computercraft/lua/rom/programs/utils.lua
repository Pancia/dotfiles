function char_to_hex(c)
  return string.format("%%%02X", string.byte(c))
end

function urlencode(url)
  if url == nil then
    return
  end
  url = url:gsub("\n", "\r\n")
  url = url:gsub("([^%w ])", char_to_hex)
  url = url:gsub(" ", "+")
  return url
end

function splitByChunk(text, chunkSize)
    local s = {}
    for i=1, #text, chunkSize do
        s[#s+1] = text:sub(i,i+chunkSize - 1)
    end
    return s
end

function formatText(width, t)
    local lines = {}
    local offsets = {}
    local i = 1
    for _, line in ipairs(t) do
        if #line > width then
            local chunks = splitByChunk(line, width)
            for ci, v in ipairs(chunks) do
                lines[i] = v
                offsets[i] = #chunks - ci + 1
                i = i+1
            end
        else
            lines[i] = line
            offsets[i] = 1
            i = i+1
        end
    end
    return lines, offsets
end

return {formatText = formatText, urlencode = urlencode}
