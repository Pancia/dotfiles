set completeopt+=noinsert
set completeopt+=noselect
set completeopt-=preview
set completeopt+=menu
set completeopt+=menuone

call SEMICOLON_GROUP('s', '+lsp')

" https://github.com/gfanto/fzf-lsp.nvim
call SEMICOLON_CMD('s?', ':LspInfo', 'LSP Info')
call SEMICOLON_CMD('sR', ':LspRestart', 'LSP Restart')
call SEMICOLON_CMD('sa', ':CodeActions', 'show available code actions')
call SEMICOLON_CMD('sd', ':Definitions', 'show the definition for the symbols under the cursor')
call SEMICOLON_CMD('sc', ':Declarations', 'show the declaration for the symbols under the cursor*')
call SEMICOLON_CMD('si', ':Implementations', 'show the implementation for the symbols under the cursor*')
call SEMICOLON_CMD('su', ':References', 'show the usages of the symbol under the cursor')
call SEMICOLON_CMD('sf', ':DocumentSymbols', 'show all the symbols in the current buffer')
call SEMICOLON_CMD('sw', ':WorkspaceSymbols', 'show all the symbols in the workspace, you can optionally pass the query as argument to the command')
call SEMICOLON_CMD('sI', ':IncomingCalls', 'show the incoming calls')
call SEMICOLON_CMD('sO', ':OutgoingCalls', 'show the outgoing calls')
call SEMICOLON_CMD('sg', ':Diagnostics', 'show all the available diagnostic informations in the current buffer, you can optionally pass the desired severity level as first argument or the severity limit level as second argument')
call SEMICOLON_CMD('sG', ':DiagnosticsAll', 'show all the available diagnostic informations in all the opened buffers, you can optionally pass the desired severity level as first argument or the severity limit level as second argument')
