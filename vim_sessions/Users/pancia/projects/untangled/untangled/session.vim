terminal zsh -is eval "lrcw '(start-figwheel)'"
file repl-client
terminal zsh -is eval "wait-for .nrepl-port lr:w '(start-demo-server)'"
file repl-server
