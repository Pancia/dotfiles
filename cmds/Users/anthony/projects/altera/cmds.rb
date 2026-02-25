module CMD
  def start(opts)
    opts.banner = "Usage: start"
    opts.info = "Start Altera and attach liaison"
    lambda { |*args|
      EXE.bash %{
        alt start; sleep 1; alt liaison attach
      }
    }
  end

  def log_live(opts)
    opts.banner = "Usage: log_live"
    opts.info = "Tail Altera logs"
    lambda { |*args|
      EXE.bash %{
        alt log --tail
      }
    }
  end

  def status_live(opts)
    opts.banner = "Usage: status_live"
    opts.info = "Live Altera status (11s interval, no events)"
    lambda { |*args|
      EXE.bash %{
        alt status --live --interval 11 --no-events
      }
    }
  end

  def docs(opts)
    opts.banner = "Usage: docs"
    opts.info = "Open TODO.md in vim"
    lambda { |*args|
      EXE.fish %{
        vim TODO.md
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
