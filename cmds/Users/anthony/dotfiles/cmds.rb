module CMD
  def test(opts)
    opts.banner = "Usage: test [component] [pytest-args...]"
    opts.info = "Run dotfiles tests. Components: youtube-transcribe, cjson, services, lib"
    lambda { |*args|
      EXE.bash %{
        uv run ~/dotfiles/lib/python/run_tests.py #{args.join " "}
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
