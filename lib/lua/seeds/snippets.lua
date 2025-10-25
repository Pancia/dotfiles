local obj = {}

-- Configuration
obj.snippets_file = os.getenv("HOME").."/ProtonDrive/_config/snippets.txt"
obj.paste_on_select = false
obj.hotkey = {{"cmd", "ctrl"}, "s"} -- Default hotkey

-- Internal storage
obj._snippets = {}
obj._chooser = nil

-- Load snippets from file
function obj:loadSnippets()
  local snippets = {}
  local file = io.open(self.snippets_file, "r")

  if not file then
    hs.notify.show("Snippets", "Could not open snippets file", self.snippets_file)
    return snippets
  end

  local current_snippet = nil

  for line in file:lines() do
    -- Check if this is a new snippet (contains ':')
    local title, content = line:match("^([^:]+):%s*(.*)$")

    if title then
      -- Save previous snippet if exists
      if current_snippet then
        table.insert(snippets, current_snippet)
      end

      -- Start new snippet
      current_snippet = {
        title = title:match("^%s*(.-)%s*$"), -- trim whitespace
        content = content
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

  file:close()

  -- Process escape sequences in all snippets
  for _, snippet in ipairs(snippets) do
    snippet.content = snippet.content:gsub("\\n", "\n")
    snippet.content = snippet.content:gsub("\\t", "\t")
  end

  return snippets
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

    table.insert(menuData, {
      text = snippet.title,
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

  -- Create the chooser
  self._chooser = hs.chooser.new(selectSnippet)
  self._chooser:choices(function() return self:populateChooser() end)
  self._chooser:searchSubText(true) -- Allow searching in content too

  -- Bind hotkey
  hs.hotkey.bindSpec(self.hotkey, function() self:toggle() end)

  return self
end

return obj
