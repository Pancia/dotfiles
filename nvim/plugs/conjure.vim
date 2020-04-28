let g:conjure_map_prefix = ","
let g:conjure_log_direction = "horizontal"
let g:conjure_log_size_small = 33
let g:conjure_nmap_toggle_log = g:conjure_map_prefix . "l"
let g:conjure_log_blacklist = ["up"] " ~> conjure_log_auto_open_blacklist

let g:conjure_log_auto_close = v:false
autocmd InsertEnter *.edn,*.clj,*.clj[cs] if bufname('') !~ 'conjure.cljc' | :call conjure#close_unused_log()
