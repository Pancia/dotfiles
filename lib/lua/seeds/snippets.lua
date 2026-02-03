local obj = {}
local perfmon = require("lib/perfmon")

-- Configuration
obj.snippets_file = os.getenv("HOME").."/ProtonDrive/_config/snippets.txt"
obj.paste_on_select = false
obj.hotkey = {{"cmd", "ctrl"}, "s"} -- Default hotkey
obj.expansion_enabled = true -- Enable/disable text expansion

-- Internal storage
obj._snippets = {}
obj._chooser = nil
obj._eventtap = nil
obj._buffer = ""
obj._triggers = {} -- Map of trigger -> snippet content
obj._max_trigger_length = 0

-- Parse snippets from file content string
function obj:parseSnippets(content)
  local snippets = {}
  local current_snippet = nil

  for line in content:gmatch("([^\n]*)\n?") do
    -- Check if this is a new snippet (contains ':')
    local title, snippet_content = line:match("^([^:]+):%s*(.*)$")

    if title then
      -- Save previous snippet if exists
      if current_snippet then
        table.insert(snippets, current_snippet)
      end

      -- Parse optional trigger from title: "My Snippet [;ms]" -> title="My Snippet", trigger=";ms"
      local clean_title, trigger = title:match("^(.-)%s*%[([^%]]+)%]%s*$")
      if not clean_title then
        clean_title = title
        trigger = nil
      end

      -- Start new snippet
      current_snippet = {
        title = clean_title:match("^%s*(.-)%s*$"), -- trim whitespace
        content = snippet_content,
        trigger = trigger
      }
    elseif current_snippet and line:match("%S") then
      -- Continue previous snippet (non-empty line without ':')
      current_snippet.content = current_snippet.content .. "\n" .. line
    elseif line == "" and current_snippet then
      -- Empty line - could be intentional newline in content
      -- Add it to preserve formatting
      current_snippet.content = current_snippet.content .. "\n"
    end
  end

  -- Don't forget the last snippet
  if current_snippet then
    table.insert(snippets, current_snippet)
  end

  -- Process escape sequences in all snippets
  for _, snippet in ipairs(snippets) do
    snippet.content = snippet.content:gsub("\\n", "\n")
    snippet.content = snippet.content:gsub("\\t", "\t")
  end

  return snippets
end

-- Load snippets from file (synchronous - for chooser)
function obj:loadSnippets()
  local file = io.open(self.snippets_file, "r")
  if not file then
    hs.notify.show("Snippets", "Could not open snippets file", self.snippets_file)
    return {}
  end
  local content = file:read("*a")
  file:close()
  return self:parseSnippets(content)
end

-- Load snippets asynchronously (for startup)
function obj:loadSnippetsAsync(callback)
  if self._loadTask then
    self._loadTask:terminate()
    self._loadTask = nil
  end

  self._loadTask = hs.task.new("/bin/cat", function(exitCode, stdout, stderr)
    self._loadTask = nil
    if exitCode ~= 0 then
      hs.notify.show("Snippets", "Could not read snippets file", stderr or "unknown error")
      if callback then callback({}) end
      return
    end
    local snippets = self:parseSnippets(stdout)
    if callback then callback(snippets) end
  end, {self.snippets_file})
  self._loadTask:start()
end

-- Build triggers map from snippets
function obj:buildTriggers()
  self._triggers = {}
  self._max_trigger_length = 0

  for _, snippet in ipairs(self._snippets) do
    if snippet.trigger then
      self._triggers[snippet.trigger] = snippet.content
      if #snippet.trigger > self._max_trigger_length then
        self._max_trigger_length = #snippet.trigger
      end
    end
  end
end

-- Delete characters by sending backspaces
local function deleteChars(count)
  for _ = 1, count do
    hs.eventtap.keyStroke({}, "delete", 0)
  end
end

-- Type text using pasteboard (faster and more reliable)
local function typeText(text)
  local oldContents = hs.pasteboard.getContents()
  hs.pasteboard.setContents(text)
  hs.eventtap.keyStroke({"cmd"}, "v", 0)
  -- Restore clipboard after a short delay
  hs.timer.doAfter(0.1, function()
    if oldContents then
      hs.pasteboard.setContents(oldContents)
    end
  end)
end

-- Handle keystrokes for text expansion
function obj:handleKeystroke(event)
  return perfmon.track("snippets.eventtap.keystroke", function()
    local keyCode = event:getKeyCode()
    local flags = event:getFlags()

    -- Ignore if modifiers are held (except shift)
    if flags.cmd or flags.alt or flags.ctrl then
      self._buffer = ""
      return false
    end

    local char = event:getCharacters()

    -- Reset buffer on certain keys
    if keyCode == hs.keycodes.map["return"] or
       keyCode == hs.keycodes.map["escape"] or
       keyCode == hs.keycodes.map["tab"] or
       keyCode == hs.keycodes.map["space"] then
      self._buffer = ""
      return false
    end

    -- Handle backspace
    if keyCode == hs.keycodes.map["delete"] then
      if #self._buffer > 0 then
        self._buffer = self._buffer:sub(1, -2)
      end
      return false
    end

    -- Only track printable characters
    if char and #char == 1 then
      self._buffer = self._buffer .. char

      -- Keep buffer limited to max trigger length
      if #self._buffer > self._max_trigger_length then
        self._buffer = self._buffer:sub(-self._max_trigger_length)
      end

      -- Check if buffer ends with any trigger
      for trigger, content in pairs(self._triggers) do
        if self._buffer:sub(-#trigger) == trigger then
          -- Found a match - delete trigger and insert content
          hs.timer.doAfter(0, function()
            deleteChars(#trigger)
            hs.timer.doAfter(0.05, function()
              typeText(content)
            end)
          end)
          self._buffer = ""
          return false
        end
      end
    end

    return false
  end)
end

-- Start the text expansion eventtap (async)
function obj:startExpansion()
  if self._eventtap then
    self._eventtap:stop()
  end

  self:loadSnippetsAsync(function(snippets)
    self._snippets = snippets
    self:buildTriggers()

    if self._max_trigger_length > 0 then
      self._eventtap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
        return self:handleKeystroke(event)
      end)
      self._eventtap:start()
    end
  end)
end

-- Stop text expansion
function obj:stopExpansion()
  if self._eventtap then
    self._eventtap:stop()
    self._eventtap = nil
  end
end

-- Reload snippets (useful after editing snippets file)
function obj:reload()
  self._snippets = self:loadSnippets()
  self:buildTriggers()
  if self._chooser then
    self._chooser:refreshChoicesCallback()
  end
  hs.notify.show("Snippets", "Reloaded", #self._snippets .. " snippets loaded")
end

-- Populate chooser with snippets
function obj:populateChooser()
  self._snippets = self:loadSnippets()
  local menuData = {}

  for _, snippet in ipairs(self._snippets) do
    -- Display title as main text, content as subtext
    local display_content = snippet.content
    if #display_content > 100 then
      display_content = display_content:sub(1, 97) .. "..."
    end

    -- Show trigger in title if present
    local display_title = snippet.title
    if snippet.trigger then
      display_title = display_title .. " [" .. snippet.trigger .. "]"
    end

    table.insert(menuData, {
      text = display_title,
      subText = display_content,
      snippet = snippet
    })
  end

  if #menuData == 0 then
    table.insert(menuData, {
      text = "No snippets found",
      subText = "Add snippets to " .. self.snippets_file,
      snippet = nil
    })
  end

  return menuData
end

-- Handle snippet selection
function selectSnippet(choice)
  if choice and choice.snippet then
    local snippet = choice.snippet
    hs.pasteboard.setContents(snippet.content)

    if obj.paste_on_select then
      hs.eventtap.keyStroke({"cmd"}, "v")
    end

    hs.notify.show("Snippet Copied", snippet.title, "Content copied to clipboard")
  end
end

-- Show the snippets chooser
function obj:show()
  if self._chooser then
    self._chooser:refreshChoicesCallback()
    self._chooser:show()
  end
end

-- Toggle snippets chooser visibility
function obj:toggle()
  if self._chooser:isVisible() then
    self._chooser:hide()
  else
    self:show()
  end
end

-- Initialize the snippets manager
function obj:start(config)
  config = config or {}

  -- Apply configuration
  if config.snippets_file then
    self.snippets_file = config.snippets_file
  end
  if config.paste_on_select ~= nil then
    self.paste_on_select = config.paste_on_select
  end
  if config.hotkey then
    self.hotkey = config.hotkey
  end
  if config.expansion_enabled ~= nil then
    self.expansion_enabled = config.expansion_enabled
  end

  -- Create the chooser (choices loaded lazily)
  self._chooser = hs.chooser.new(selectSnippet)
  self._chooser:choices(function() return self:populateChooser() end)
  self._chooser:searchSubText(true) -- Allow searching in content too

  -- Bind hotkey
  self._hotkey = hs.hotkey.bindSpec(self.hotkey, function() self:toggle() end)

  -- Start expansion asynchronously (ProtonDrive I/O can be slow)
  if self.expansion_enabled then
    self:startExpansion()
  end

  return self
end

function obj:stop()
  self:stopExpansion()
  if self._loadTask then
    self._loadTask:terminate()
    self._loadTask = nil
  end
  if self._chooser then
    self._chooser:delete()
    self._chooser = nil
  end
  if self._hotkey then
    self._hotkey:delete()
    self._hotkey = nil
  end
end

return obj
