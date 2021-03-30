module CMD
  def test(opts)
    opts.banner = "Usage: test"
    opts.info = "Run clojure tests"
    lambda { |*args|
      EXE.system %{
        clj \
          -J-Dguardrails.enabled=true \
          -A:tee:dev:test:run-tests:spec-dev:gr-dev \
          --config-file tests.local.edn \
          --focus-meta :test/focused \
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
        clj -A:nREVL:dev:test:spec-dev:gr-dev #{args.join " "}
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
