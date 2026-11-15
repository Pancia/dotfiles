-- Per-pane nvim session for `revive` (docs/revive.md, "nvim sessions").
--
-- The `nvim` fish wrapper sets REVIVE_NVIM_DIR for its own child only, when the
-- shell journals its pane. This nvim then keeps a `mksession` of itself in
-- <dir>/<pid>.vim, rewritten a moment after the layout or the cursor changes.
-- A clean exit deletes it, so only a hard death (power cut, SIGKILL) leaves one,
-- and the next shell in the pane carries it into the ghost with the record.
--
-- A power cut gives no exit hook, so the file must always be on disk. The write
-- goes to <pid>.vim.tmp, is flushed (libuv's fsync is F_FULLFSYNC on macOS), and
-- only then renamed over the real one. A cut mid-write keeps the last file.

local M = {}

-- No `blank`, `help` or `terminal`: a restored terminal re-runs its command,
-- and revive never runs a command without asking. No `options`: the config
-- already sets them.
local OPTS = 'buffers,curdir,folds,tabpages,winsize'

local st = {
    path = nil, tmp = nil, timer = nil, due = 0,
    busy = false, again = false, leaving = false, last = nil,
}

local function remove_files()
    if st.path then
        os.remove(st.tmp)
        os.remove(st.path)
    end
end

local save

-- Save within `ms`. A save already due sooner stands: CursorHold fires 200 ms
-- into every pause, and resetting the timer let it push a layout save from
-- 300 ms back to 2 s.
local function later(ms)
    if st.leaving then return end
    local due = vim.uv.now() + ms
    if st.timer:is_active() and st.due <= due then return end
    st.due = due
    st.timer:stop()
    st.timer:start(ms, 0, vim.schedule_wrap(function() save() end))
end

-- Called back on the main loop once the rename is done (or failed)
local function finished(body, ok)
    st.busy = false
    if ok then st.last = body end
    if st.leaving then
        remove_files()
        return
    end
    if st.again then
        st.again = false
        later(300)
    end
end

save = function()
    if st.leaving or not st.path then return end
    -- mid-restore, or on the way out: the window layout is not the real one
    if vim.g.SessionLoad == 1 or vim.v.exiting ~= vim.NIL then return end
    if st.busy then
        st.again = true
        return
    end

    -- Plugin buffers (undotree, fugitive, conjure log) have a buftype. Unlisted
    -- for the length of one mksession, they are left out of the file. Events
    -- are off meanwhile: toggling buflisted fires BufDelete and BufAdd, which
    -- re-armed this save (36 events in 2.5 s idle) and told every plugin a
    -- buffer had gone.
    local ei, so, this = vim.o.eventignore, vim.o.sessionoptions, vim.v.this_session
    vim.o.eventignore = 'all'
    local hidden = {}
    local ok = pcall(function()
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
            if vim.bo[b].buflisted and vim.bo[b].buftype ~= '' then
                vim.bo[b].buflisted = false
                table.insert(hidden, b)
            end
        end
        vim.o.sessionoptions = OPTS
        vim.cmd('silent! mksession! ' .. vim.fn.fnameescape(st.tmp))
    end)
    -- mksession points v:this_session at its file; SessionSave must not see it
    vim.o.sessionoptions = so
    vim.v.this_session = this
    for _, b in ipairs(hidden) do
        if vim.api.nvim_buf_is_valid(b) then vim.bo[b].buflisted = true end
    end
    vim.o.eventignore = ei
    if not ok then return end

    local f = io.open(st.tmp, 'r')
    if not f then return end
    local body = f:read('*a')
    f:close()
    if body == st.last then
        os.remove(st.tmp)
        return
    end

    st.busy = true
    local tmp, path = st.tmp, st.path
    local done = vim.schedule_wrap(finished)
    vim.uv.fs_open(tmp, 'r+', 438, function(err, fd)
        if err then return done(body, false) end
        vim.uv.fs_fsync(fd, function()
            vim.uv.fs_close(fd, function()
                if st.leaving then
                    -- quit while flushing: a rename now would bring the file back
                    vim.uv.fs_unlink(tmp, function() done(body, false) end)
                    return
                end
                vim.uv.fs_rename(tmp, path, function(rerr) done(body, rerr == nil) end)
            end)
        end)
    end)
end

function M.setup()
    if vim.g.vscode then return end
    local dir = vim.env.REVIVE_NVIM_DIR
    -- Unset at once, so nothing this nvim starts (`:!`, `:terminal`, git's
    -- editor) can claim the pane as well
    vim.env.REVIVE_NVIM_DIR = nil
    if not dir or dir == '' then return end
    if vim.fn.mkdir(dir, 'p') == 0 and vim.fn.isdirectory(dir) == 0 then return end

    st.path = dir .. '/' .. vim.fn.getpid() .. '.vim'
    st.tmp = st.path .. '.tmp'
    st.timer = vim.uv.new_timer()

    local group = vim.api.nvim_create_augroup('revive_session', { clear = true })
    vim.api.nvim_create_autocmd({
        'VimEnter', 'BufEnter', 'WinNew', 'WinClosed', 'TabNew', 'TabClosed',
        'BufDelete', 'DirChanged', 'VimResized', 'VimResume', 'FocusLost',
        'SessionLoadPost',
    }, { group = group, callback = function() later(300) end })
    -- updatetime is 200 ms, so this fires once per pause; the debounce keeps
    -- cursor-only saves to one per pause at most
    vim.api.nvim_create_autocmd('CursorHold', {
        group = group, callback = function() later(2000) end,
    })
    vim.api.nvim_create_autocmd('VimLeavePre', {
        group = group,
        callback = function()
            st.leaving = true
            st.timer:stop()
            remove_files()
        end,
    })
end

-- For tests: write now, skipping the debounce
M._save = function() save() end
M._state = st

return M
