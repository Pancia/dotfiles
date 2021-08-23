let g:conjure#log#hud#width = "0.50"
let g:conjure#log#hud#height = "0.50"
let g:conjure#mapping#doc_word = "k"
let g:conjure#mapping#def_word = "gd"
let g:conjure#log#wrap = v:true
let g:conjure#highlight#enabled = v:false

let g:conjure#client#clojure#nrepl#completion#with_context = v:false
let g:conjure#client#clojure#nrepl#test#current_form_names = ['deftest', 'specification']
"FIXME?
"let g:conjure#client#clojure#nrepl#test#runner = 'kaocha'
"let g:conjure#client#clojure#nrepl#test#call_suffix = '{:kaocha/color? true :config-file "tests.local.edn"}'

let g:conjure#filetype#fennel = "conjure.client.fennel.stdio"
let g:conjure#client#fennel#stdio#command = "hs-fennel"
let g:conjure#debug = v:false
