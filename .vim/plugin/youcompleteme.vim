let g:UltiSnipsExpandTrigger="<ctrl><tab>" "TODO: <ctrl|alt|...>-enter?
let g:ycm_semantic_triggers = {'haskell' : ['.']}
"
"Helps with cpp and synastic
"https://github.com/Valloric/YouCompleteMe#the-gycm_show_diagnostics_ui-option
let g:ycm_show_diagnostics_ui = 0

"Enables & configures semantic completion for c,c++...
let g:ycm_global_ycm_extra_conf = "~/.vim/.ycm_extra_conf.py"

let g:ycm_autoclose_preview_window_after_insertion = 1
