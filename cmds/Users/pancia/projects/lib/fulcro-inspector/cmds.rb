# require's go here

module CMD
  def shadow(opts)
    opts.banner = "Usage: shadow"
    opts.info = "Start shadow-cljs with all electron related builds."
    lambda { |*args|
      command = %{
        shadow-cljs watch test-app electron-main electron-renderer electron-sandbox base-visualizers
      }
      EXE.execute(command)
    }
  end
  def electron(opts)
    opts.banner = "Usage: electron"
    opts.info = "Start electron."
    lambda { |*args|
      command = %{
        (cd out/electron; electron .)
      }
      EXE.execute(command)
    }
  end
  def server(opts)
    opts.banner = "Usage: server"
    opts.info = "Start server repl."
    lambda { |*args|
      command = %{
        clj -A:nREPL:test-app
      }
      EXE.execute(command)
    }
  end
end

trap "SIGINT" do
  exit 130
end
