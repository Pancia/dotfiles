local HOME = os.getenv("HOME")
package.path = HOME.."/dotfiles/nvim/lua/?.lua;" .. package.path
package.path = HOME.."/.config/nvim/plugged/conjure/lua/?.lua;" .. package.path

require('plugs/hop')
if not vim.g.vscode then
    require('plugs/lsp')
    require('plugs/cmp')
end

-- :Regenerate — re-run the `generate:` frontmatter command and replace the file body
vim.api.nvim_create_user_command('MarkdownRegenerate', function()
    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    -- Find frontmatter delimiters (line 1 must be ---)
    if lines[1] ~= '---' then
        vim.notify('No frontmatter found (first line must be ---)', vim.log.levels.ERROR)
        return
    end
    local close_idx
    for i = 2, #lines do
        if lines[i] == '---' then
            close_idx = i
            break
        end
    end
    if not close_idx then
        vim.notify('No closing --- found in frontmatter', vim.log.levels.ERROR)
        return
    end

    -- Extract generate: value (YAML literal block scalar |)
    local front_lines = {}
    for i = 2, close_idx - 1 do
        table.insert(front_lines, lines[i])
    end
    local cmd_lines = {}
    local in_generate = false
    for _, line in ipairs(front_lines) do
        if not in_generate then
            if line:match('^generate:%s*|%s*$') then
                in_generate = true
            elseif line:match('^generate:%s+(.+)$') then
                -- Single-line generate value
                table.insert(cmd_lines, line:match('^generate:%s+(.+)$'))
                break
            end
        else
            -- Indented continuation lines belong to the block scalar
            if line:match('^%s+') then
                table.insert(cmd_lines, line:match('^%s+(.*)$'))
            else
                break
            end
        end
    end
    if #cmd_lines == 0 then
        vim.notify('No generate: key found in frontmatter', vim.log.levels.ERROR)
        return
    end
    local cmd = table.concat(cmd_lines, '\n')

    -- Determine repo root
    local file_dir = vim.fn.expand('%:p:h')
    local root = vim.fn.system('git -C ' .. vim.fn.shellescape(file_dir) .. ' rev-parse --show-toplevel 2>/dev/null'):gsub('%s+$', '')
    if root == '' then
        root = file_dir
    end

    -- Execute via /bin/sh to avoid Fish shell hooks polluting stdout
    local result = vim.fn.systemlist({'/bin/sh', '-c', 'cd ' .. vim.fn.shellescape(root) .. ' && ' .. cmd})
    if vim.v.shell_error ~= 0 then
        vim.notify('generate command failed (exit ' .. vim.v.shell_error .. '): ' .. table.concat(result, '\n'), vim.log.levels.ERROR)
        return
    end

    -- Replace everything after closing --- (preserve frontmatter + blank line)
    local new_lines = {}
    for i = 1, close_idx do
        table.insert(new_lines, lines[i])
    end
    table.insert(new_lines, '')
    for _, line in ipairs(result) do
        table.insert(new_lines, line)
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
    vim.notify('Regenerated (' .. #result .. ' lines)', vim.log.levels.INFO)
end, {})

vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        if vim.fn.argc() == 0 then
            -- Show your custom content
            vim.cmd("enew")
            local lines = {
                "Welcome back Commander! o7",
            }
            vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
            vim.bo.modifiable = false
            vim.bo.buftype = 'nofile'
        end
    end
})
