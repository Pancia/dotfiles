local obj = {}

-- ============================================================================
-- PROVIDER SYSTEM
-- ============================================================================

-- Provider registry
obj._providers = {}

-- Register a provider with a prefix (or nil for default provider)
function obj:registerProvider(prefix, provider)
  if prefix == nil then
    self._defaultProvider = provider
  else
    self._providers[prefix] = provider
  end
end

-- Get provider for a given query
function obj:getProviderForQuery(query)
  if query and #query > 0 then
    local firstChar = query:sub(1, 1)
    if self._providers[firstChar] then
      return self._providers[firstChar], query:sub(2) -- Strip prefix
    end
  end
  return self._defaultProvider, query
end

-- ============================================================================
-- FUZZY MATCHING
-- ============================================================================

-- Fuzzy match scoring function
-- Returns: (matched: boolean, score: number)
-- Higher scores indicate better matches
function fuzzyMatch(str, query)
  if not query or #query == 0 then
    return true, 0
  end

  local lowerStr = str:lower()
  local lowerQuery = query:lower()

  local score = 0
  local queryIndex = 1
  local consecutiveMatches = 0
  local lastMatchIndex = 0

  for i = 1, #lowerStr do
    if queryIndex > #lowerQuery then
      break
    end

    local strChar = lowerStr:sub(i, i)
    local queryChar = lowerQuery:sub(queryIndex, queryIndex)

    if strChar == queryChar then
      -- Base score for matching character
      score = score + 10

      -- Bonus for consecutive matches
      if i == lastMatchIndex + 1 then
        consecutiveMatches = consecutiveMatches + 1
        score = score + (consecutiveMatches * 5)
      else
        consecutiveMatches = 0
      end

      -- Bonus for matching at word boundaries
      if i == 1 then
        -- Start of string
        score = score + 15
      elseif i > 1 then
        local prevChar = lowerStr:sub(i - 1, i - 1)
        local origChar = str:sub(i, i)
        -- Capital letter in original (word boundary in camelCase)
        if origChar:match("%u") then
          score = score + 10
        -- After space or special character
        elseif prevChar:match("[%s%-_/]") then
          score = score + 10
        end
      end

      -- Bonus for earlier matches (diminishing)
      score = score + math.max(0, 50 - i)

      lastMatchIndex = i
      queryIndex = queryIndex + 1
    end
  end

  -- Check if all query characters were matched
  if queryIndex > #lowerQuery then
    return true, score
  else
    return false, 0
  end
end

-- ============================================================================
-- APPLICATION PROVIDER
-- ============================================================================

local ApplicationProvider = {}

function ApplicationProvider:new()
  local instance = {}
  setmetatable(instance, { __index = ApplicationProvider })
  -- Enable Spotlight for alternate app name searches
  hs.application.enableSpotlightForNameSearches(true)
  return instance
end

function ApplicationProvider:getChoices(query)
  local choices = {}
  local apps = hs.application.runningApplications()

  -- Get all installed applications
  local allApps = {}
  for _, app in ipairs(apps) do
    local name = app:name()
    if name then
      allApps[name] = app
    end
  end

  -- Also scan /Applications for installed apps
  local applicationsPath = "/Applications"
  for file in hs.fs.dir(applicationsPath) do
    if file:match("%.app$") then
      local appName = file:gsub("%.app$", "")
      if not allApps[appName] then
        allApps[appName] = applicationsPath .. "/" .. file
      end
    end
  end

  -- Filter and create choices
  for name, app in pairs(allApps) do
    local matched, score = fuzzyMatch(name, query)
    if matched then
      -- Get application icon
      local icon = nil
      if type(app) == "string" then
        -- Installed app - get icon from app path
        icon = hs.image.imageFromPath(app)
      else
        -- Running app - get icon from bundle ID
        local bundleID = app:bundleID()
        if bundleID then
          icon = hs.image.imageFromAppBundle(bundleID)
        end
      end

      -- Resize icon to consistent size if available
      if icon then
        icon = icon:setSize({w = 32, h = 32})
      end

      table.insert(choices, {
        text = name,
        subText = type(app) == "string" and "Launch" or "Running",
        image = icon,
        appName = name,
        appPath = type(app) == "string" and app or nil,
        appObj = type(app) ~= "string" and app or nil,
        score = score
      })
    end
  end

  -- Sort by score (descending), then alphabetically
  table.sort(choices, function(a, b)
    if a.score == b.score then
      return a.text < b.text
    else
      return a.score > b.score
    end
  end)

  return choices
end

function ApplicationProvider:selectItem(item)
  if item then
    if item.appObj then
      -- App is already running, focus it
      item.appObj:activate()
    elseif item.appPath then
      -- Launch the app
      hs.application.open(item.appName)
    end
  end
end

-- ============================================================================
-- STUB PROVIDERS (for future extension)
-- ============================================================================

-- VPC PROVIDER (must be defined before SlashProvider)
local VpcProvider = {}

function VpcProvider:new()
  local instance = {}
  setmetatable(instance, { __index = VpcProvider })
  instance.vpcDir = os.getenv("HOME") .. "/dotfiles/vpc/"
  return instance
end

function VpcProvider:getChoices(query)
  local choices = {}

  -- Scan vpc directory for .vpc files
  for file in hs.fs.dir(self.vpcDir) do
    if file:match("%.vpc$") then
      local vpcName = file:gsub("%.vpc$", "")
      local fullPath = self.vpcDir .. file

      -- Filter by query using fuzzy matching
      local matched, score = fuzzyMatch(vpcName, query)
      if matched then
        -- Try to parse VPC file for metadata
        local subText = "VPC Workspace"
        local fileHandle = io.open(fullPath, "r")
        if fileHandle then
          local content = fileHandle:read("*all")
          fileHandle:close()

          -- Parse JSON to extract metadata
          local ok, vpcData = pcall(function() return hs.json.decode(content) end)
          if ok and vpcData then
            local parts = {}
            if vpcData.space then
              table.insert(parts, "Space " .. vpcData.space)
            end
            if vpcData.iterm then
              table.insert(parts, "iTerm")
            end
            if vpcData.chrome then
              table.insert(parts, "Chrome")
            end
            if vpcData.brave then
              table.insert(parts, "Brave")
            end
            if vpcData.apps then
              table.insert(parts, "Apps")
            end
            if vpcData.board then
              table.insert(parts, "Board")
            end
            if #parts > 0 then
              subText = table.concat(parts, " • ")
            end
          end
        end

        table.insert(choices, {
          text = "/vpc " .. vpcName,
          subText = subText,
          vpcPath = fullPath,
          score = score
        })
      end
    end
  end

  -- Sort by score (descending), then alphabetically
  table.sort(choices, function(a, b)
    if a.score == b.score then
      return a.text < b.text
    else
      return a.score > b.score
    end
  end)

  return choices
end

function VpcProvider:selectItem(item)
  if item and item.vpcPath then
    -- Open the .vpc file (Automator will handle it)
    -- Escape single quotes for shell safety
    local escapedPath = item.vpcPath:gsub("'", "'\"'\"'")
    hs.execute("open '" .. escapedPath .. "'")
  end
end

-- SLASH PROVIDER
local SlashProvider = {}

function SlashProvider:new()
  local instance = {}
  setmetatable(instance, { __index = SlashProvider })
  instance.vpcProvider = VpcProvider:new()
  return instance
end

function SlashProvider:getChoices(query)
  local trimmedQuery = query or ""

  -- Get all VPC choices (without filtering)
  local allVpcChoices = self.vpcProvider:getChoices("")

  -- Apply fuzzy matching on full display text
  local matches = {}
  for _, choice in ipairs(allVpcChoices) do
    -- choice.text is "/vpc simplymeet", we match against "vpc simplymeet"
    local textWithoutSlash = choice.text:sub(2) -- Remove leading "/"
    local matched, score = fuzzyMatch(textWithoutSlash, trimmedQuery)

    if matched then
      choice.score = score
      choice.provider = "vpc"
      table.insert(matches, choice)
    end
  end

  -- Sort by score (descending), then alphabetically
  table.sort(matches, function(a, b)
    if a.score == b.score then
      return a.text < b.text
    else
      return a.score > b.score
    end
  end)

  -- If query is empty, show help text as first item
  if trimmedQuery == "" then
    table.insert(matches, 1, {
      text = "vpc <name>",
      subText = "Search and launch VPC workspaces",
      isHelp = true
    })
  end

  -- If no matches found, show unknown command
  if #matches == 0 then
    return {
      {
        text = "/" .. trimmedQuery,
        subText = "Unknown slash command. Try: /vpc",
        isStub = true
      }
    }
  end

  return matches
end

function SlashProvider:selectItem(item)
  if item and item.isHelp then
    -- Don't do anything for help items
    return
  end

  if item and item.provider == "vpc" then
    self.vpcProvider:selectItem(item)
  else
    hs.alert.show("Unknown slash command")
  end
end

-- BANG PROVIDER
local BangProvider = {}

function BangProvider:new()
  local instance = {}
  setmetatable(instance, { __index = BangProvider })
  return instance
end

function BangProvider:getChoices(query)
  return {
    {
      text = "Bang command: " .. (query or ""),
      subText = "This provider is not yet implemented",
      isStub = true
    }
  }
end

function BangProvider:selectItem(item)
  -- Future: implement bang commands
  hs.alert.show("Bang commands not yet implemented")
end

-- ============================================================================
-- WINDOW SWITCHER (original functionality)
-- ============================================================================

function selectItem(item)
  if item then
    item.window:focus()
  end
  obj._chooser:query(nil)
  for _, b in pairs(obj._bindings) do
    b:disable()
  end
end

function obj:navdown()
  obj._chooser:selectedRow(obj._chooser:selectedRow()+1)
end

function obj:navup()
  obj._chooser:selectedRow(obj._chooser:selectedRow()-1)
end

function obj:populateChooser()
  local menuData = {}
  local windows = obj._wf:getWindows()
  for _, w in pairs(windows) do
    local app = w:application():name()
    local title = w:title()
    table.insert(menuData, {text=title.." #"..app, subText=app, window=w})
  end
  return menuData
end

function obj:show()
  obj._chooser:refreshChoicesCallback()
  obj._chooser:show()
  for _, b in pairs(obj._bindings) do
    b:enable()
  end
  obj:navdown()
end

function obj:showOrNext()
  if obj._chooser:isVisible() then
    obj:navdown()
  else
    obj:show()
  end
end

function obj:showOrPrev()
  if obj._chooser:isVisible() then
    obj:navup()
  else
    obj:show()
  end
end

-- ============================================================================
-- APP LAUNCHER (new functionality)
-- ============================================================================

function selectAppLauncherItem(item)
  if item and not item.isStub then
    local provider = obj._currentProvider or obj._defaultProvider
    if provider and provider.selectItem then
      provider:selectItem(item)
    end
  elseif item and item.isStub then
    local provider = obj._currentProvider
    if provider and provider.selectItem then
      provider:selectItem(item)
    end
  end
  obj._appLauncher:query(nil)
  for _, b in pairs(obj._appLauncherBindings) do
    b:disable()
  end
end

function obj:populateAppLauncher()
  local query = obj._appLauncher:query() or ""
  local provider, strippedQuery = obj:getProviderForQuery(query)
  obj._currentProvider = provider

  if provider and provider.getChoices then
    return provider:getChoices(strippedQuery)
  end

  return {}
end

function obj:appLauncherNavDown()
  obj._appLauncher:selectedRow(obj._appLauncher:selectedRow()+1)
end

function obj:appLauncherNavUp()
  obj._appLauncher:selectedRow(obj._appLauncher:selectedRow()-1)
end

function obj:showAppLauncher()
  obj._appLauncher:refreshChoicesCallback()
  obj._appLauncher:show()
  for _, b in pairs(obj._appLauncherBindings) do
    b:enable()
  end
  obj:appLauncherNavDown()
end

function obj:hideAppLauncher()
  obj._appLauncher:hide()
  for _, b in pairs(obj._appLauncherBindings) do
    b:disable()
  end
end

function obj:start()
  -- Window switcher (original functionality)
  hs.hotkey.bindSpec({{"alt", "ctrl"}, "tab"}, obj.showOrNext)
  hs.hotkey.bindSpec({{"alt", "ctrl", "shift"}, "tab"}, obj.showOrPrev)
  obj._wf = hs.window.filter.new(true):setCurrentSpace(nil):keepActive()
  obj._chooser = hs.chooser.new(selectItem)
  obj._chooser:choices(obj.populateChooser)
  obj._bindings = {}
  table.insert(obj._bindings, hs.hotkey.new({"ctrl"}, "j", obj.navdown))
  table.insert(obj._bindings, hs.hotkey.new({"ctrl"}, "k", obj.navup))

  -- App launcher (new functionality)
  -- Initialize providers
  obj:registerProvider(nil, ApplicationProvider:new())  -- Default provider
  obj:registerProvider("/", SlashProvider:new())
  obj:registerProvider("!", BangProvider:new())

  -- Create app launcher chooser
  obj._appLauncher = hs.chooser.new(selectAppLauncherItem)
  obj._appLauncher:choices(function() return obj:populateAppLauncher() end)
  obj._appLauncher:queryChangedCallback(function()
    obj._appLauncher:refreshChoicesCallback()
  end)

  -- Setup navigation bindings for app launcher
  obj._appLauncherBindings = {}
  table.insert(obj._appLauncherBindings, hs.hotkey.new({"ctrl"}, "j", function() obj:appLauncherNavDown() end))
  table.insert(obj._appLauncherBindings, hs.hotkey.new({"ctrl"}, "k", function() obj:appLauncherNavUp() end))

  -- Bind Cmd-Space to show app launcher
  hs.hotkey.bindSpec({{"cmd"}, "space"}, function() obj:showAppLauncher() end)

  return obj
end

return obj
