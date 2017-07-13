terminal zsh -is eval "lrcw '(start-figwheel)'"
file repl-client
terminal zsh -is eval "wait-for .nrepl-port lr:w '(server-test-server)'"
file tests-server
terminal zsh -is eval "wait-for .nrepl-port lr:w '(run-demo-server)'"
file repl-server
