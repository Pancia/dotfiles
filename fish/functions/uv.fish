function uv --wraps uv
    set -lx UV_PROJECT_ENVIRONMENT ~/.local/state/uv$PWD/.venv
    command uv $argv
end
