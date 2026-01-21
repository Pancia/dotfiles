# pyenv configuration
set -gx PYENV_ROOT "$HOME/.pyenv"
if test -d "$PYENV_ROOT/bin"
    fish_add_path --prepend "$PYENV_ROOT/bin"
end
if command -v pyenv >/dev/null
    pyenv init - fish | source
end
