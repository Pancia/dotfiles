module CMD
  def timer(opts)
    opts.banner = "Usage: timer"
    opts.info = "Run sanctuary timer"
    lambda { |*args|
      EXE.bash %{
        fish timer.fish
      }
    }
  end

  def main(opts)
    opts.banner = "Usage: main [args...]"
    opts.info = "Run main sanctuary session"
    lambda { |*args|
      EXE.bash %{
        fish main-claude.fish #{args.join " "}
      }
    }
  end

  def minimal(opts)
    opts.banner = "Usage: minimal"
    opts.info = "Quick sanctuary: focus, state, pomodoro, journal, edit"
    lambda { |*args|
      EXE.bash %{
        fish main-claude.fish minimal #{args.join " "}
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
