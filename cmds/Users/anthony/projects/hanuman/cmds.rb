module CMD
  def start(opts)
    opts.banner = "Usage: start FIXME"
    opts.info = "FIXME"
    lambda { |*args|
      EXE.bash %{
        uv run python main.py
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
