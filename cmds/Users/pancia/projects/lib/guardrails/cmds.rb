module CMD
  def test(opts)
    opts.banner = "Usage: test"
    opts.info = "run the clojure tests"
    lambda { |*args|
      EXE.system %{
        clj \
          -A:spec-dev:dev:test:clj-tests \
          -J-Dguardrails.enabled=true \
          -J-Dguardrails.config=guardrails-test.edn \
          --watch
      }
    }
  end
  def repl(opts)
    opts.banner = "Usage: repl"
    opts.info = "run the clojure repl"
    lambda { |*args|
      EXE.system %{
        clj -A:nREPL:dev:test
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
