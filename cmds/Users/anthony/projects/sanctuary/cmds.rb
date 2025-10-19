module CMD
  def start(opts)
    opts.banner = "Usage: start"
    opts.info = "start"
    lambda { |*args|
      EXE.system %{
        npm run dev
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
