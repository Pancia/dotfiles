module CMD
  def ai_import(opts)
    opts.banner = "Usage: ai_import [-p PLAYLIST] [-d DIR]"
    opts.info = "AI-powered import from ytdl music inbox"
    lambda { |*args|
      EXE.bash %{
        music ai_import #{args.join " "}
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
