module CMD
  def test(opts)
    opts.banner = "Usage: test [component] [pytest-args...]"
    opts.info = "Run dotfiles tests. Components: yt, python, astro, fish, hooks, roleplay, svc, bin; or a file under tests/"
    lambda { |*args|
      EXE.bash %{
        uv run ~/dotfiles/lib/python/run_tests.py #{args.shelljoin}
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
