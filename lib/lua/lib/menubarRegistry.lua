-- Menubar Registry: Persists menubar objects across soft reloads
--
-- The key insight: _G globals survive package.loaded cache clearing.
-- This allows menubars to persist when we re-require seed modules,
-- preserving their macOS object identity (which Hidden Bar tracks).

local M = {}

-- Global registry that persists across soft reloads
if not rawget(_G, "__MENUBAR_REGISTRY__") then
    rawset(_G, "__MENUBAR_REGISTRY__", {})
end

local registry = rawget(_G, "__MENUBAR_REGISTRY__")

-- Get existing menubar or create new one
-- Returns: menubar, isNew (boolean)
function M.getOrCreate(name)
    if registry[name] then
        return registry[name], false
    end

    -- Create new menubar with autosaveName for position persistence
    local mb = hs.menubar.new(true, name)
    registry[name] = mb
    return mb, true
end

-- Get existing menubar (nil if doesn't exist)
function M.get(name)
    return registry[name]
end

-- Delete menubar and remove from registry (for hard reload)
function M.delete(name)
    local mb = registry[name]
    if mb then
        mb:delete()
        registry[name] = nil
    end
end

-- List all registered menubar names
function M.list()
    local names = {}
    for name, _ in pairs(registry) do
        table.insert(names, name)
    end
    return names
end

-- Check if menubar exists in registry
function M.exists(name)
    return registry[name] ~= nil
end

return M
