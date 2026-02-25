module CMD
  def service_restart(opts)
    opts.banner = "Usage: service_restart"
    opts.info = "Restart sanctuary service and tail logs"
    lambda { |*args|
      EXE.bash %{
        service restart sanctuary && service log sanctuary
      }
    }
  end
  def dev(opts)
    opts.banner = "Usage: dev"
    opts.info = "Run npm dev server"
    lambda { |*args|
      EXE.bash %{
        npm run dev
      }
    }
  end
  def vim(opts)
    opts.banner = "Usage: vim"
    opts.info = "Open project files in nvim"
    lambda { |*args|
      EXE.bash %{
        nvim documents/hello-world.md index.html
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
