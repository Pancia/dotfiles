function uv --wraps uv
    set -lx UV_PROJECT_ENVIRONMENT ~/.state/uv$PWD/.venv
    command uv $argv
end
