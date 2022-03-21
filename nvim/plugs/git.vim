call SEMICOLON_GROUP('g', '+git')


call SEMICOLON_GROUP('ga', '+git add')
call SEMICOLON_CMD('gaf', ':Git add %', 'add this file')
call SEMICOLON_CMD('ga.', ':Git add .', 'add this directory')
call SEMICOLON_CMD('gaa', ':Git add --all', 'add all')
call SEMICOLON_CMD('gap', ':Git add --patch', 'add interactively')


call SEMICOLON_CMD('gb', ':Git blame', 'git blame')


call SEMICOLON_GROUP('gc', '+git commit')
call SEMICOLON_CMD('gcc', ':Git commit --verbose', 'commit')
call SEMICOLON_CMD('gca', ':Git commit --verbose --all', 'commit all')
call SEMICOLON_CMD('gcp', ':Git commit --patch', 'commit interactively')


call SEMICOLON_GROUP('gd', '+git diff')
call SEMICOLON_CMD('gdd', ':Git diff', 'diff')
call SEMICOLON_CMD('gds', ':Git diff --staged', 'diff staged')


call SEMICOLON_GROUP('gg', '+git gutter')
call SEMICOLON_CMD('ggp', ':GitGutterPreviewHunk', 'View Changes')
call SEMICOLON_CMD('gga', ':GitGutterStageHunk', 'Stage Hunk')


call SEMICOLON_GROUP('gp', '+git push')
call SEMICOLON_CMD('gpp', ':Git push', 'Push')


call SEMICOLON_CMD('gs', ':Git', 'git status')
