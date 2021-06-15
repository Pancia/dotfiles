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
        clj -A:nREPL:dev
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
