module CMD
  def start(opts)
    opts.banner = "Usage: start"
    opts.info = "start"
    lambda { |*args|
      EXE.system %{
        npm start
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
