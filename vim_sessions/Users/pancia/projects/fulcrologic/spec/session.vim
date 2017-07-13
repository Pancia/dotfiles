term zsh -is eval 'wait-for .nrepl-port lein cljsbuild auto spec-renderer'
file cljsbuild
term zsh -is eval 'lrcw "(start-figwheel)"'
file client-repl
term zsh -is eval 'wait-for .nrepl-port lr:w "(start)"'
file server-repl
