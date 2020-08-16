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
