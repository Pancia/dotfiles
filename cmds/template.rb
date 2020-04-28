require "optparse"

def execute(command)
  temp = "/tmp/command.zsh"
  pretty_command = command.lstrip.split(/\s\s+/).join(" \\\n")
  system("echo '#{pretty_command}' > #{temp} && bat #{temp}")
  system(command)
end

module CMD
  def example_opts()
    OptionParser.new do |opts|
      opts.banner = "Usage: example"
      opts.info = "FIXME"
    end
  end
  def example(*args)
    command = %{
      echo "FIXME"
    }
    execute(command)
  end
end

trap "SIGINT" do
  exit 130
end
