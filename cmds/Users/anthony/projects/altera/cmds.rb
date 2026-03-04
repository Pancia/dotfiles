module CMD
  def start(opts)
    opts.banner = "Usage: start"
    opts.info = "Start Altera and attach liaison"
    lambda { |*args|
      EXE.bash %{
        alt start; alt liaison attach
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
        alt status --live --interval 30 --no-events
      }
    }
  end

  def scenario(opts)
    opts.banner = "Usage: scenario [args...]"
    opts.info = "Run an e2e test scenario via scripts/run-manual-test"
    lambda { |*args|
      EXE.bash %{
        ./scripts/run-manual-test #{args.join " "}
      }
    }
  end

  def sandbox(opts)
    opts.banner = "Usage: sandbox [name]"
    opts.info = "Create a fresh blank project in /tmp/altera-tests for exploratory testing"
    lambda { |*args|
      name = args.first || "sandbox"
      EXE.bash %{
        ./scripts/sandbox "#{name}"
      }
    }
  end

  def claude(opts)
    opts.banner = "Usage: claude"
    opts.info = "Launch Claude Code wrapper"
    lambda { |*args|
      EXE.fish %{
        set -l timestamp (date +%H:%M:%S)
        set -l label (basename (pwd))
        set label "$label $timestamp"
        proc-label "claude [$label]" alt ai run claude #{args.join " "}
      }
    }
  end

  def docs(opts)
    opts.banner = "Usage: docs"
    opts.info = "Open TODO.md in vim"
    lambda { |*args|
      EXE.fish %{
        vim altera/sitrep.md TODO.md docs/roadmap.md
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
