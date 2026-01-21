module CMD
  def start(opts)
    opts.banner = "Usage: start FIXME"
    opts.info = "FIXME"
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
