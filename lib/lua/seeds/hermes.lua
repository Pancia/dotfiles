local obj = {}

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
end

function obj:start()
  obj._wf = hs.window.filter.new(true):setCurrentSpace(nil):keepActive()
  obj._chooser = hs.chooser.new(selectItem)
  obj._chooser:choices(obj.populateChooser)
  obj._bindings = {}
  table.insert(obj._bindings, hs.hotkey.new({"ctrl"}, "j", obj.navdown))
  table.insert(obj._bindings, hs.hotkey.new({"ctrl"}, "k", obj.navup))
  return obj
end

return obj
