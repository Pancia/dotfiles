let s:session_loc = g:vims_sessions_root . getcwd() . '/' . g:vims_session_type . '.vim'
if filereadable(s:session_loc)
    execute 'source ' . s:session_loc
endif
