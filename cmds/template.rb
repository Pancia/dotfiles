module CMD
  def example(opts)
    opts.banner = "Usage: example"
    opts.info = "FIXME"
    lambda { |*args|
      command = %{
        echo "FIXME"
      }
      EXE.system(command)
    }
  end
end

trap "SIGINT" do
  exit 130
end
