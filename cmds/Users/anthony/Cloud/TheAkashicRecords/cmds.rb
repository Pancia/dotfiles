module CMD
  def start(opts)
    opts.banner = "Usage: start"
    opts.info = "Launch Claude Code with personal assistant prompt"
    lambda { |*args|
      EXE.fish %{
          my-claude-code-wrapper --process-label assistant --system-prompt (cat personal-assistant-prompt.txt | string collect)
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
