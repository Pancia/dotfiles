require "optparse"

def execute(command)
  temp = "/tmp/command.zsh"
  pretty_command = command.lstrip.split(/\s\s+/).join(" \\\n")
  system("echo '#{pretty_command}' > #{temp} && bat #{temp}")
  system(command)
end

module CMD
  def dev_opts()
    OptionParser.new do |opts|
      opts.banner = "Usage: dev"
      opts.info = "Start gondola server with dev & test, prepl, & other necessities..."
    end
  end
  def dev(*args)
    command = %{
    environment=clearfork-dev \
        clj \
        -J-Ddev -J-Dtest \
        -J-Denvironment=clearfork-dev \
        -J-Dconfig=config/dev-tony.edn \
        -J-Dguardrails.enabled=true \
        -J-Dallow.mocked.connection=true \
        -J-Dclojure.server.jvm="{:port 5678 :accept clojure.core.server/io-prepl}" \
        -A:dev:test
    }
    execute(command)
  end
end

trap "SIGINT" do
  exit 130
end
