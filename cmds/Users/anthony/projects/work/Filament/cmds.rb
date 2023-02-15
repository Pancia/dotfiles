module CMD
  def shadow(opts)
    lambda { |*args|
      EXE.system %{
        npx shadow-cljs watch test ci-tests \
          electron-background electron-renderer \
          electron-meta-devtools
      }
    }
  end
  def electron(opts)
    lambda { |*args|
      EXE.system %{
        wait-for .shadow-cljs/electron-renderer.status electron .
      }
    }
  end
  def repl(opts)
    lambda { |*args|
      EXE.system %{
        clj -A:local/nREPL:dev:test #{args.join " "}
      }
    }
  end
  def clean(opts)
    lambda { |*args|
      EXE.system %{
        trash .shadow-cljs resources/public/js/
      }
    }
  end
  def test_clojure(opts)
    lambda { |*args|
      EXE.system %{
        clojure -A:dev:test:local/spec-dev \
          -J-Dguardrails.config=guardrails-test.edn \
          -m kaocha.runner \
          :clojure-unit \
          #{args.join " "}
      }
    }
  end
  def test_cljs(opts)
    lambda { |*args|
      EXE.system %{
        wait-for .shadow-cljs/ci-tests.status npx karma start #{args.join " "}
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
