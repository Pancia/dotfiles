module CMD
  def example(opts)
    opts.banner = "Usage: example"
    opts.info = "FIXME"
    lambda { |*args|
      EXE.bash %{
        echo "FIXME"
      }
    }
  end

  def start(opts)
    opts.banner = "Usage: start FIXME"
    opts.info = "FIXME"
    lambda { |*args|
      EXE.fish %{
          my-claude-code-wrapper --system-prompt (cat personal-assistant-prompt.txt | string collect)
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
