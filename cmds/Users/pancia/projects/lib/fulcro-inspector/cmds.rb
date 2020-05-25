# require's go here

def execute(command)
  temp = "/tmp/command.zsh"
  pretty_command = command.lstrip.split(/\s\s+/).join(" \\\n")
  system("echo '#{pretty_command}' > #{temp} && bat #{temp}")
  system(command)
end

module CMD
  def shadow(opts)
    opts.banner = "Usage: shadow"
    opts.info = "Start shadow-cljs with all electron related builds."
    lambda { |*args|
      command = %{
        shadow-cljs watch test-app electron-main electron-renderer electron-sandbox base-visualizers
      }
      execute(command)
    }
  end
  def electron(opts)
    opts.banner = "Usage: electron"
    opts.info = "Start electron."
    lambda { |*args|
      command = %{
        (cd out/electron; electron .)
      }
      execute(command)
    }
  end
  def server(opts)
    opts.banner = "Usage: server"
    opts.info = "Start server repl."
    lambda { |*args|
      command = %{
        clj -A:nREPL:test-app
      }
      execute(command)
    }
  end
end

trap "SIGINT" do
  exit 130
end
