augroup ProjectMarkers
    au!
    au Syntax * syn match MyProjectTask     /\v<(TASK)(:.*)?/
          \ containedin=.*Comment,vimCommentTitle
    au Syntax * syn match MyProjectNote     /\v<(NOTE)(:.*)?/
          \ containedin=.*Comment,vimCommentTitle
    au Syntax * syn match MyProjectLandmark /\v<(LANDMARK)(:.*)?/
          \ containedin=.*Comment,vimCommentTitle
    au Syntax * syn match MyProjectContext  /\v<(CONTEXT)(:.*)?/
          \ containedin=.*Comment,vimCommentTitle
    au Syntax * syn match MyProjectContext  /\v<(CONTEXT)(:.*)?/
          \ containedin=.*Comment,vimCommentTitle
    au Syntax * call matchadd('MyProjectTodo', '\v<(TODO)(:.*)?', 100)
    au Syntax * call matchadd('MyProjectFixme', '\v<(FIXME)(:.*)?', 100)
augroup END

hi MyProjectTodo     guifg=#BB22DD
" TODO asdf TODO: slkjs iafdlk
"
hi MyProjectFixme    guifg=#FFFB00
" FIXME asdf FIXME: lkasb lnasd
"
hi MyProjectTask     guifg=#BF1020
" TASK asdf TASK: laksnla k ajds
"
hi MyProjectNote     guifg=#1FC5C8
" NOTE asdf NOTE: lk akdl jasdf
"
hi MyProjectLandmark guifg=#17C80D
" LANDMARK asdf LANDMARK: bo asdf
"
hi MyProjectContext  guifg=#DF447B
" CONTEXT asdf CONTEXT: foo bar
