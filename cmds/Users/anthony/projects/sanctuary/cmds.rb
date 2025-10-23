module CMD
  def start(opts)
    opts.banner = "Usage: start"
    opts.info = "start"
    lambda { |*args|
      EXE.system %{
        npm run dev
      }
    }
  end
  def vim(opts)
    opts.banner = "Usage: vim"
    opts.info = "vim"
    lambda { |*args|
      EXE.system %{
        nvim documents/hello-world.md index.html
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
