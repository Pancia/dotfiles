function! s:AddProjectMarkers() abort
    if index(['markdown', 'text', 'plain', 'help'], &filetype) >= 0
        return
    endif
    syn match MyProjectTask      /\v\C<(TASK)(:.*)?/
          \ contained containedin=.*Comment,vimCommentTitle
    syn match MyProjectNote      /\v\C<(NOTE)(:.*)?/
          \ contained containedin=.*Comment,vimCommentTitle
    syn match MyProjectLandmark  /\v\C<(LANDMARK)(:.*)?/
          \ contained containedin=.*Comment,vimCommentTitle
    syn match MyProjectContext   /\v\C<(CONTEXT)(:.*)?/
          \ contained containedin=.*Comment,vimCommentTitle
    syn match MyProjectTranslate /\v\C<(TRANSLATE)(:.*)?/
          \ contained containedin=.*Comment,vimCommentTitle
    syn match MyProjectResumeHere /\v\C<(RESUMEHERE)(:.*)?/
          \ contained containedin=.*Comment,vimCommentTitle
    syn match MyProjectTodo      /\v\C<(TODO)(:.*)?/
          \ contained containedin=.*Comment,vimCommentTitle
    syn match MyProjectFixme     /\v\C<(FIXME)(:.*)?/
          \ contained containedin=.*Comment,vimCommentTitle
endfunction

augroup ProjectMarkers
    au!
    au Syntax * call s:AddProjectMarkers()
augroup END

" TRANSLATE: asdf
