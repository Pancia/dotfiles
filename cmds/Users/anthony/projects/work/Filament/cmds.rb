module CMD
  def shadow(opts)
    opts.banner = "Usage: shadow"
    opts.info = "Watch shadow-cljs builds (test, ci-tests, electron)"
    lambda { |*args|
      EXE.bash %{
        npx shadow-cljs watch test ci-tests \
          electron-background electron-renderer \
          electron-meta-devtools
      }
    }
  end
  def electron(opts)
    opts.banner = "Usage: electron"
    opts.info = "Launch Electron after shadow-cljs renderer is ready"
    lambda { |*args|
      EXE.bash %{
        wait-for .shadow-cljs/electron-renderer.status electron .
      }
    }
  end
  def repl(opts)
    opts.banner = "Usage: repl [args...]"
    opts.info = "Start Clojure nREPL with dev and test aliases"
    lambda { |*args|
      EXE.bash %{
        clj -A:local/nREPL:dev:test #{args.join " "}
      }
    }
  end
  def clean(opts)
    opts.banner = "Usage: clean"
    opts.info = "Trash shadow-cljs cache and compiled JS"
    lambda { |*args|
      EXE.bash %{
        trash .shadow-cljs resources/public/js/
      }
    }
  end
  def test_clojure(opts)
    opts.banner = "Usage: test_clojure [args...]"
    opts.info = "Run Clojure unit tests via kaocha"
    lambda { |*args|
      EXE.bash %{
        clojure -A:dev:test:local/spec-dev \
          -J-Dguardrails.config=guardrails-test.edn \
          -m kaocha.runner \
          :clojure-unit \
          #{args.join " "}
      }
    }
  end
  def test_cljs(opts)
    opts.banner = "Usage: test_cljs [args...]"
    opts.info = "Run ClojureScript tests via Karma"
    lambda { |*args|
      EXE.bash %{
        wait-for .shadow-cljs/ci-tests.status npx karma start #{args.join " "}
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
