set completeopt+=noinsert
set completeopt+=noselect
set completeopt-=preview
set completeopt+=menu
set completeopt+=menuone

call SEMICOLON_GROUP('l', '+lsp')

" https://github.com/gfanto/fzf-lsp.nvim
call SEMICOLON_CMD('l?', ':LspInfo', 'LSP Info')
call SEMICOLON_CMD('lR', ':LspRestart', 'LSP Restart')
call SEMICOLON_CMD('la', ':CodeActions', 'show available code actions')
call SEMICOLON_CMD('ld', ':Definitions', 'show the definition for the symbols under the cursor')
call SEMICOLON_CMD('lc', ':Declarations', 'show the declaration for the symbols under the cursor*')
call SEMICOLON_CMD('li', ':Implementations', 'show the implementation for the symbols under the cursor*')
call SEMICOLON_CMD('lu', ':References', 'show the usages of the symbol under the cursor')
call SEMICOLON_CMD('lf', ':DocumentSymbols', 'show all the symbols in the current buffer')
call SEMICOLON_CMD('lw', ':WorkspaceSymbols', 'show all the symbols in the workspace, you can optionally pass the query as argument to the command')
call SEMICOLON_CMD('lI', ':IncomingCalls', 'show the incoming calls')
call SEMICOLON_CMD('lO', ':OutgoingCalls', 'show the outgoing calls')
call SEMICOLON_CMD('lg', ':Diagnostics', 'show all the available diagnostic informations in the current buffer, you can optionally pass the desired severity level as first argument or the severity limit level as second argument')
call SEMICOLON_CMD('lG', ':DiagnosticsAll', 'show all the available diagnostic informations in all the opened buffers, you can optionally pass the desired severity level as first argument or the severity limit level as second argument')
