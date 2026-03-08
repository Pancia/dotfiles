module CMD
  def start(opts)
    opts.banner = "Usage: start"
    opts.info = "Start Altera and tmux attach to tui"
    lambda { |*args|
      EXE.bash %{
        alt start --no-attach
        alt tmux attach alt-liaison
      }
    }
  end

  def dashboard(opts)
    opts.banner = "Usage: dashboard"
    opts.info = "Live Altera tui dashboard"
    lambda { |*args|
      EXE.fish %{
        while not alt tmux run has-session -t alt-main 2>/dev/null; sleep 0.2; end; alt tmux attach alt-main
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

  def roadmap(opts)
    opts.banner = "Usage: roadmap"
    opts.info = "Open TODO.md in vim"
    lambda { |*args|
      EXE.fish %{
        vim altera/sitrep.md TODO.md docs/roadmap.md docs/launch-plan.md
      }
    }
  end

  def business(opts)
    opts.banner = "Usage: business"
    opts.info = "Open TODO.md in vim"
    lambda { |*args|
      EXE.fish %{
        vim docs/business-model.md
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
