module CMD
  def service_restart(opts)
    opts.banner = "Usage: service_restart"
    opts.info = "service_restart"
    lambda { |*args|
      EXE.bash %{
        service restart sanctuary && service log sanctuary
      }
    }
  end
  def dev(opts)
    opts.banner = "Usage: dev"
    opts.info = "dev"
    lambda { |*args|
      EXE.bash %{
        npm run dev
      }
    }
  end
  def vim(opts)
    opts.banner = "Usage: vim"
    opts.info = "vim"
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
