module CMD
  def start(opts)
    opts.banner = "Usage: start"
    opts.info = "Run Flutter app"
    lambda { |*args|
      EXE.bash %{
        flutter run
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
