-- Safe logger that wraps hs.logger with pcall to handle IPC errors
-- Drop-in replacement for hs.logger.new
local M = {}

function M.new(name, level)
    local logger = hs.logger.new(name, level)
    local wrapped = {}
    for _, method in ipairs({'i', 'd', 'w', 'e', 'f', 'v', 'df', 'ef', 'wf', 'vf', 'if'}) do
        wrapped[method] = function(...)
            pcall(logger[method], ...)
        end
    end
    return wrapped
end

return M
