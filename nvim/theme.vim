syntax on
set termguicolors "enables gui*

" NOTE: MUST BE BEFORE `colorscheme onedark`
let g:onedark_color_overrides = {
\ "black":          {"gui": "#FFFFFF", "cterm": "NONE"},
\ "white":          {"gui": "#000000", "cterm": "NONE"},
\ "blue":           {"gui": "#2653F0", "cterm": "NONE"},
\ "cyan":           {"gui": "#37B5C2", "cterm": "NONE"},
\ "green":          {"gui": "#2FAC1F", "cterm": "NONE"},
\ "purple":         {"gui": "#BC28B9", "cterm": "NONE"},
\ "red":            {"gui": "#E00013", "cterm": "NONE"},
\ "yellow":         {"gui": "#EEA209", "cterm": "NONE"},
\ "dark_yellow":    {"gui": "#D1853A", "cterm": "NONE"},
\ "comment_grey":   {"gui": "#5C6370", "cterm": "NONE"},
\ "cursor_grey":    {"gui": "#F0F0F0", "cterm": "NONE"},
\ "gutter_fg_grey": {"gui": "#60697F", "cterm": "NONE"},
\ "menu_grey":      {"gui": "#C0C0C0", "cterm": "NONE"},
\ "special_grey":   {"gui": "#FD6608", "cterm": "NONE"},
\ "visual_black":   {"gui": "#000000", "cterm": "NONE"},
\ "visual_grey":    {"gui": "#AEC0EC", "cterm": "NONE"},
\}
colorscheme onedark

hi Folded guifg=#67EAEA guibg=#808080

hi MatchParen gui=standout
hi illuminatedWord gui=standout

hi EasyMotionIncSearch gui=standout

hi Search guibg=black guifg=#FFF900

hi MyProjectTodo      guifg=#BB22DD gui=standout
" TODO asdf TODO: asdf asdf
"
hi MyProjectTask      guifg=#BF1020 gui=standout
" TASK asdf TASK: asdf asdf
"
hi MyProjectNote      guifg=#1FC5C8 gui=standout
" NOTE asdf NOTE: asdf asdf
"
hi MyProjectLandmark  guifg=#17C80D gui=standout
" LANDMARK asdf LANDMARK: asdf asdf
"
hi MyProjectContext   guifg=#DF447B gui=standout
" CONTEXT asdf CONTEXT: asdf asdf
"
hi MyProjectTranslate guifg=#F244E7 gui=standout
" TRANSLATE asdf TRANSLATE: asdf asdf

call onedark#set_highlight("MyProjectFixme", {"fg": g:onedark_color_overrides.yellow
            \                                ,"bg": g:onedark_color_overrides.white
            \                                ,"gui": "standout"})
" FIXME asdf FIXME: asdf asdf
