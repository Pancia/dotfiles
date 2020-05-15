let g:conjure_config = {
      \ "log.hud.width" : "0.55",
      \ "log.hud.height": "0.75",
      \ "mappings.doc-word": "k",
      \ "mappings.def-word": "gd",
      \ }

let g:unite_source_menu_menus.conjure = {'description' : 'Conjure Commands'}
let g:unite_source_menu_menus.conjure.command_candidates = [
      \['restart', "ConjureEval (require 'development)(in-ns 'development)(restart)"],
      \]
