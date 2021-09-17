module CMD
  def shadow(opts)
    lambda { |*args|
      EXE.system %{
        shadow-cljs watch main
      }
    }
  end
  def repl(opts)
    lambda { |*args|
      EXE.system %{
        clj -A:local/nREFL:dev:test #{args.join " "}
      }
    }
  end
  def test(opts)
    lambda { |*args|
      EXE.system %{
        clojure -A:dev:test:spec-dev \
          -m kaocha.runner \
          --watch \
          #{args.join " "}
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
