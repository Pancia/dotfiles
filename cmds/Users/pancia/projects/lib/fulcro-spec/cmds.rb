module CMD
  def test(opts)
    opts.banner = "Usage: test"
    opts.info = "Run clojure tests"
    lambda { |*args|
      EXE.system %{
        clj -A:clj-tests \
        --watch \
        #{args.join " "}
      }
    }
  end
  def repl(opts)
    opts.banner = "Usage: repl"
    opts.info = "Run clojure repl"
    lambda { |*args|
      EXE.system %{
        clj -A:nREPL:test #{args.join " "}
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
