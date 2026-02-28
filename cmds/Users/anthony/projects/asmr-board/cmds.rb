module CMD
  def start(opts)
    opts.banner = "Usage: start"
    opts.info = "Run main.py via uv"
    lambda { |*args|
      EXE.bash %{
        uv run --with setproctitle proc-label asmr-board python main.py
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
