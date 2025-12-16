module CMD
  def timer(opts)
    opts.banner = "Usage: timer"
    opts.info = "timer"
    lambda { |*args|
      EXE.system %{
        fish timer.fish
      }
    }
  end

  def main(opts)
    opts.banner = "Usage: main"
    opts.info = "main"
    lambda { |*args|
      EXE.system %{
        fish main.fish
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
