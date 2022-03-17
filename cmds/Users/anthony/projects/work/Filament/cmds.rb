module CMD
  def shadow(opts)
    lambda { |*args|
      EXE.system %{
        shadow-cljs watch test electron-main electron-renderer
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
  def vim(opts)
    lambda { |*args|
      EXE.system %{
        nvim --listen filament.socket #{args.join " "}
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
  def test(opts)
    lambda { |*args|
      EXE.system %{
        clj -A:dev:test:local/spec-dev \
          -m kaocha.runner \
          :clojure-unit \
          #{args.join " "}
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
