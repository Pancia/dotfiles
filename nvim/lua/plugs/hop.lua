-- also see [[~/dotfiles/nvim/plugs/easymotion.vim]]

require('hop').setup()

vim.api.nvim_set_keymap('', '<space>w', "<cmd>:HopWordAC<cr>", {})
vim.api.nvim_set_keymap('', '<space>b', "<cmd>:HopWordBC<cr>", {})
vim.api.nvim_set_keymap('', '<space>j', "<cmd>:HopLineStartAC<cr>", {})
vim.api.nvim_set_keymap('', '<space>k', "<cmd>:HopLineStartBC<cr>", {})

vim.api.nvim_set_keymap('n', 'f', "<cmd>lua require'hop'.hint_char1({ direction = require'hop.hint'.HintDirection.AFTER_CURSOR })<cr>", {})
vim.api.nvim_set_keymap('n', 'F', "<cmd>lua require'hop'.hint_char1({ direction = require'hop.hint'.HintDirection.BEFORE_CURSOR })<cr>", {})
vim.api.nvim_set_keymap('n', 't', "<cmd>lua require'hop'.hint_char1({ direction = require'hop.hint'.HintDirection.AFTER_CURSOR })<cr>", {})
vim.api.nvim_set_keymap('n', 'T', "<cmd>lua require'hop'.hint_char1({ direction = require'hop.hint'.HintDirection.BEFORE_CURSOR })<cr>", {})
